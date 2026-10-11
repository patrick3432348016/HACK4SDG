"""成员 B 文档入面「A 必须提供的业务 API」：由成员 A 喺呢个服务入面用 Supabase 实现（2026-10-11）。

同 B 嘅 Business 一样嘅接口（identity / context / execute / reconcile），所以 B 嘅 Assistant 流程、确认卡、
幂等、唔重试等规则完全唔使改。

- 身份：用户嘅 Supabase access token（App 匿名登录得到）→ Supabase `GET /auth/v1/user` 核实，唔收客户端自报 id。
  核实结果按 token 摘要缓存 60 秒（唔超过 token 本身过期时间）。
- 联系人：`my_neighbors()`（RLS：只有互为街坊）。
- 地点 / 步行 / 遮荫：App 喺手机计好再上传（POST /v1/assistant/context）；服务器冇坐标，只有地标名、分钟数同遮荫比例。
- 写入：约人 = 插入 meetups（RLS 只准约互为街坊）；请假 = upsert leaves；改网名 = 更新 profiles.nickname。
  每个 (用户, operation_id) 只写一次：回执存喺 B 嘅 SQLite；约人嘅 meetups.id 由 (用户, operation_id) 推导（uuid5），
  就算回执未写低进程就死咗，再查都搵得返。
"""
from __future__ import annotations

from datetime import date, datetime, timedelta, timezone
import base64
import hashlib
import json
import time
import uuid

import httpx
from pydantic import BaseModel, ConfigDict, Field, ValidationError, field_validator

from .errors import AssistantError
from .models import Context, Execution

HK = timezone(timedelta(hours=8))
MEETUP_NAMESPACE = uuid.UUID("6f1c2a52-7d0e-4f0a-9a57-5a3b1f0c9e11")


def meetup_id(owner: str, operation_id: str) -> str:
    return str(uuid.uuid5(MEETUP_NAMESPACE, f"{owner.lower()}:{operation_id}"))


class _Model(BaseModel):
    model_config = ConfigDict(extra="forbid", str_strip_whitespace=True, allow_inf_nan=False)


class ShadeSlot(_Model):
    start: datetime
    end: datetime
    fraction: float = Field(ge=0, le=1)

    @field_validator("start", "end")
    @classmethod
    def aware(cls, v):
        if v.utcoffset() is None:
            raise ValueError("timezone required")
        return v


class UploadedPlace(_Model):
    """App 上传嘅一个地标。冇坐标（extra=forbid：传 pos / lat / lng 会被拒绝）。"""
    id: str = Field(min_length=1, max_length=100)
    name: str = Field(min_length=1, max_length=100)              # 而家手机上显示嘅名（可能用户改过）
    publish_name: str | None = Field(default=None, max_length=100)  # 上传 / 对方对得上嘅原名
    has_seat: bool = False
    self_walk_minutes: float | None = Field(default=None, ge=0, le=1000)
    contact_walk_minutes: dict[str, float] = Field(default_factory=dict)
    shade: list[ShadeSlot] = Field(default_factory=list, max_length=500)


class UploadedContext(_Model):
    places: list[UploadedPlace] = Field(default_factory=list, max_length=60)
    walk_source: str = Field(default="", max_length=200)
    shade_source: str = Field(default="", max_length=200)


class SupabaseBusiness:
    def __init__(self, settings, client: httpx.AsyncClient, store, clock=None):
        self.settings, self.client, self.store = settings, client, store
        self.base = settings.supabase_url.rstrip("/")
        self.clock = clock or (lambda: datetime.now(HK))
        self.identities: dict[str, tuple[str, float]] = {}
        with store.connection() as db:
            db.executescript("""
                CREATE TABLE IF NOT EXISTS app_context (
                    owner TEXT PRIMARY KEY, version TEXT NOT NULL, payload TEXT NOT NULL, updated REAL NOT NULL);
                CREATE TABLE IF NOT EXISTS business_receipts (
                    owner TEXT NOT NULL, operation_id TEXT NOT NULL, payload_hash TEXT NOT NULL, kind TEXT NOT NULL,
                    status TEXT NOT NULL, receipt_id TEXT, message TEXT NOT NULL DEFAULT '', detail TEXT NOT NULL DEFAULT '{}',
                    updated REAL NOT NULL, PRIMARY KEY (owner, operation_id));
            """)

    # ── HTTP ──

    def headers(self, token, **extra):
        return {"apikey": self.settings.supabase_key, "Authorization": "Bearer " + token, **extra}

    async def call(self, method, path, token, *, ok=(200, 201, 204), **kwargs):
        try:
            response = await self.client.request(method, self.base + path, headers=self.headers(token, **kwargs.pop("headers", {})), **kwargs)
        except httpx.HTTPError as exc:
            raise AssistantError("BUSINESS_UNAVAILABLE", "业务服务暂时不可用，请稍后重试。", 503) from exc
        return response

    @staticmethod
    def body(response):
        try:
            return response.json() if response.content else None
        except ValueError as exc:
            raise AssistantError("BUSINESS_INVALID", "业务服务返回了无效数据。", 502) from exc

    # ── 身份 ──

    @staticmethod
    def token_expiry(token: str) -> float | None:
        try:
            payload = token.split(".")[1]
            data = json.loads(base64.urlsafe_b64decode(payload + "=" * (-len(payload) % 4)))
            return float(data["exp"])
        except Exception:
            return None

    async def identity(self, token: str) -> str:
        digest = hashlib.sha256(token.encode()).hexdigest()
        now = time.time()
        hit = self.identities.get(digest)
        if hit and hit[1] > now:
            return hit[0]
        response = await self.call("GET", "/auth/v1/user", token)
        if response.status_code in (401, 403):
            raise AssistantError("UNAUTHORIZED", "登录已失效或没有操作权限。", 401)
        if not response.is_success:
            raise AssistantError("BUSINESS_UNAVAILABLE", "业务服务未能完成请求。", 503)
        data = self.body(response)
        user_id = data.get("id") if isinstance(data, dict) else None
        if not isinstance(user_id, str) or not 1 <= len(user_id) <= 200:
            raise AssistantError("BUSINESS_INVALID", "业务登录信息无效。", 502)
        expiry = min(now + 60, self.token_expiry(token) or now + 60)
        if len(self.identities) > 2000:
            self.identities.clear()
        self.identities[digest] = (user_id.lower(), expiry)
        return user_id.lower()

    # ── 上下文 ──

    def save_context(self, owner: str, uploaded: UploadedContext) -> str:
        payload = uploaded.model_dump(mode="json")
        raw = json.dumps(payload, ensure_ascii=False, sort_keys=True)
        version = hashlib.sha256(raw.encode()).hexdigest()[:16]
        with self.store.connection() as db:
            db.execute("INSERT INTO app_context VALUES (?,?,?,?) ON CONFLICT(owner) DO UPDATE SET version=excluded.version,"
                       " payload=excluded.payload, updated=excluded.updated", (owner, version, raw, time.time()))
        return version

    def uploaded(self, owner: str) -> tuple[str, UploadedContext | None]:
        with self.store.connection() as db:
            row = db.execute("SELECT version, payload FROM app_context WHERE owner=?", (owner,)).fetchone()
        if row is None:
            return "none", None
        return row["version"], UploadedContext.model_validate(json.loads(row["payload"]))

    async def neighbours(self, token):
        response = await self.call("POST", "/rest/v1/rpc/my_neighbors", token, json={})
        if response.status_code in (401, 403):
            raise AssistantError("UNAUTHORIZED", "登录已失效或没有操作权限。", 401)
        if not response.is_success:
            raise AssistantError("BUSINESS_UNAVAILABLE", "业务服务未能完成请求。", 503)
        rows = self.body(response)
        if not isinstance(rows, list):
            raise AssistantError("BUSINESS_INVALID", "业务服务返回了无效数据。", 502)
        return [r for r in rows if isinstance(r, dict) and isinstance(r.get("id"), str) and isinstance(r.get("nickname"), str)]

    async def context(self, token, now, starts_at=None):
        owner = await self.identity(token)
        at = starts_at or now
        rows = await self.neighbours(token)
        uploaded_version, uploaded = self.uploaded(owner)
        contacts = [{"id": r["id"].lower(), "name": r["nickname"][:100], "aliases": []} for r in rows]
        contact_ids = {c["id"] for c in contacts}
        places = []
        for p in (uploaded.places if uploaded else []):
            slot = next((s for s in p.shade if s.start <= at < s.end), None)
            places.append({
                "id": p.id, "name": p.name, "description": "有櫈" if p.has_seat else "",
                # 户外地标：App 声明长开（冇开放时间数据嘅地标唔会上传）
                "is_open": True,
                "self_walk_minutes": p.self_walk_minutes,
                "contact_walk_minutes": {k.lower(): v for k, v in p.contact_walk_minutes.items() if k.lower() in contact_ids},
                "shade_fraction": slot.fraction if slot else None,
                "shade_valid_from": slot.start if slot else None,
                "shade_valid_until": slot.end if slot else None,
                "source": (uploaded.shade_source or "街坊行手机遮荫估算（按楼宇影子，集合点）")[:200] if slot else "",
            })
        version = uploaded_version + ":" + hashlib.sha256(",".join(sorted(contact_ids)).encode()).hexdigest()[:8]
        try:
            return Context.model_validate({"version": version, "contacts": contacts, "places": places})
        except ValidationError as exc:
            raise AssistantError("BUSINESS_INVALID", "业务数据不符合接口约定。", 502) from exc

    # ── 写入 ──

    def receipt(self, owner, operation_id):
        with self.store.connection() as db:
            row = db.execute("SELECT * FROM business_receipts WHERE owner=? AND operation_id=?", (owner, operation_id)).fetchone()
        return dict(row) if row else None

    def record(self, owner, operation_id, payload_hash, kind, status, receipt_id=None, message="", detail=None):
        with self.store.connection() as db:
            db.execute("INSERT INTO business_receipts VALUES (?,?,?,?,?,?,?,?,?) ON CONFLICT(owner, operation_id) DO UPDATE SET "
                       "status=excluded.status, receipt_id=excluded.receipt_id, message=excluded.message, detail=excluded.detail,"
                       " updated=excluded.updated",
                       (owner, operation_id, payload_hash, kind, status, receipt_id, message, json.dumps(detail or {}), time.time()))

    @staticmethod
    def place_reason(place, shade, partner_minutes):
        """约会理由（粤语，同 App 嘅 honestReason 一样讲法）。"""
        parts = []
        if shade is not None:
            parts.append("嗰陣有樓遮住" if shade >= 0.5 else "嗰陣會曬")
        if place.has_seat:
            parts.append("有櫈")
        longest = max([m for m in (place.self_walk_minutes, partner_minutes) if m is not None], default=None)
        if longest is not None:
            parts.append(f"兩個都行 {max(1, round(longest))} 分鐘左右")
        return "、".join(parts)

    async def execute(self, token, owner, draft_id, payload):
        action = payload["action"]
        payload_hash = hashlib.sha256(json.dumps(action, sort_keys=True).encode()).hexdigest()
        existing = self.receipt(owner, draft_id)
        if existing:
            if existing["payload_hash"] != payload_hash:
                return Execution(status="rejected", message="同一个操作编号对应唔同内容，已拒绝。")
            if existing["status"] in {"succeeded", "rejected"}:
                return Execution(status=existing["status"], receipt_id=existing["receipt_id"], message=existing["message"])
            return await self.reconcile(token, owner, draft_id)
        self.record(owner, draft_id, payload_hash, action["kind"], "pending", detail=action)
        # 版本：确认卡生成之后联系人 / 地点有变（例如解除咗街坊）就唔写。
        context = await self.context(token, self.clock(), datetime.fromisoformat(action["starts_at"]) if action.get("starts_at") else None)
        if payload.get("expected_context_version") != context.version:
            return self.finish(owner, draft_id, payload_hash, action, "rejected", None, "资料已经更新，请重新提出请求。")
        kind = action["kind"]
        if kind == "invite":
            return await self.invite(token, owner, draft_id, payload_hash, action, context)
        if kind == "leave":
            day = date.fromisoformat(action["date"])
            response = await self.call("POST", "/rest/v1/leaves", token, params={"on_conflict": "user_id,day"},
                                       headers={"Prefer": "resolution=merge-duplicates,return=minimal"},
                                       json={"user_id": owner, "day": day.isoformat()})
            return self.outcome(response, owner, draft_id, payload_hash, action, f"leave-{day.isoformat()}")
        if kind == "rename":
            name = action["new_name"]
            if not 1 <= len(name) <= 20:
                return self.finish(owner, draft_id, payload_hash, action, "rejected", None, "网名要 1 至 20 个字。")
            response = await self.call("PATCH", "/rest/v1/profiles", token, params={"id": f"eq.{owner}"},
                                       headers={"Prefer": "return=representation"},
                                       json={"nickname": name, "updated_at": datetime.now(timezone.utc).isoformat()})
            if response.is_success and not self.body(response):
                return self.finish(owner, draft_id, payload_hash, action, "rejected", None, "未有个人资料，改唔到网名。")
            return self.outcome(response, owner, draft_id, payload_hash, action, f"nickname-{draft_id[:12]}")
        return self.finish(owner, draft_id, payload_hash, action, "rejected", None, "不支持的操作。")

    async def invite(self, token, owner, draft_id, payload_hash, action, context):
        contact = next((c for c in context.contacts if c.id == action["contact_id"]), None)
        _, uploaded = self.uploaded(owner)
        place = next((p for p in (uploaded.places if uploaded else []) if p.id == action["place_id"]), None)
        starts_at = datetime.fromisoformat(action["starts_at"])
        if contact is None:
            return self.finish(owner, draft_id, payload_hash, action, "rejected", None, "对方已经唔系你嘅街坊。")
        if place is None:
            return self.finish(owner, draft_id, payload_hash, action, "rejected", None, "地点已经唔喺附近。")
        if starts_at <= self.clock():
            return self.finish(owner, draft_id, payload_hash, action, "rejected", None, "集合时间已过。")
        ctx_place = next((p for p in context.places if p.id == place.id), None)
        reason = self.place_reason(place, ctx_place.shade_fraction if ctx_place else None, place.contact_walk_minutes.get(contact.id))
        row_id = meetup_id(owner, draft_id)
        row = {"id": row_id, "inviter": owner, "invitee": contact.id, "at": starts_at.astimezone(timezone.utc).isoformat(),
               "landmark_name": place.publish_name or place.name, "reason": reason, "status": "waiting",
               "updated_by": owner, "updated_at": datetime.now(timezone.utc).isoformat()}
        response = await self.call("POST", "/rest/v1/meetups", token, headers={"Prefer": "return=minimal"}, json=row)
        if response.status_code == 409:
            # 已经插入过（之前超时 / 进程中断）：同一个 id 喺度就当成功
            found = await self.meetup_exists(token, row_id)
            if found:
                return self.finish(owner, draft_id, payload_hash, action, "succeeded", row_id, "")
        return self.outcome(response, owner, draft_id, payload_hash, action, row_id)

    def outcome(self, response, owner, draft_id, payload_hash, action, receipt_id):
        if response.is_success:
            return self.finish(owner, draft_id, payload_hash, action, "succeeded", receipt_id, "")
        if response.status_code in (401, 403):
            # RLS 拒绝（例如唔系互为街坊）：确定冇写入
            return self.finish(owner, draft_id, payload_hash, action, "rejected", None, "冇权限：对方要同你互为街坊。")
        if response.status_code in (400, 404, 409, 422):
            return self.finish(owner, draft_id, payload_hash, action, "rejected", None, "资料唔啱，冇写入。")
        # 5xx / 429：唔知写咗未。交返 B 嘅流程标记「结果不确定」，之后用 reconcile 查。
        raise AssistantError("BUSINESS_UNAVAILABLE", "业务服务暂时不可用。", 503)

    def finish(self, owner, draft_id, payload_hash, action, status, receipt_id, message):
        self.record(owner, draft_id, payload_hash, action["kind"], status, receipt_id, message, action)
        return Execution(status=status, receipt_id=receipt_id, message=message)

    async def meetup_exists(self, token, row_id):
        response = await self.call("GET", "/rest/v1/meetups", token, params={"select": "id", "id": f"eq.{row_id}"})
        if not response.is_success:
            raise AssistantError("BUSINESS_UNAVAILABLE", "业务服务暂时不可用。", 503)
        return bool(self.body(response))

    async def reconcile(self, token, owner, draft_id):
        existing = self.receipt(owner, draft_id)
        if existing and existing["status"] in {"succeeded", "rejected"}:
            return Execution(status=existing["status"], receipt_id=existing["receipt_id"], message=existing["message"])
        if existing is None:
            # 回执都未写低：约人仍然可以按推导出嚟嘅 id 去 Supabase 查
            row_id = meetup_id(owner, draft_id)
            if await self.meetup_exists(token, row_id):
                return Execution(status="succeeded", receipt_id=row_id)
            return Execution(status="not_found")
        action = json.loads(existing["detail"] or "{}")
        kind = existing["kind"]
        if kind == "invite":
            row_id = meetup_id(owner, draft_id)
            if await self.meetup_exists(token, row_id):
                return self.finish(owner, draft_id, existing["payload_hash"], action, "succeeded", row_id, "")
        elif kind == "leave" and action.get("date"):
            response = await self.call("GET", "/rest/v1/leaves", token, params={"select": "day", "user_id": f"eq.{owner}", "day": f"eq.{action['date']}"})
            if response.is_success and self.body(response):
                return self.finish(owner, draft_id, existing["payload_hash"], action, "succeeded", f"leave-{action['date']}", "")
        elif kind == "rename" and action.get("new_name"):
            response = await self.call("GET", "/rest/v1/profiles", token, params={"select": "nickname", "id": f"eq.{owner}"})
            rows = self.body(response) if response.is_success else None
            if rows and rows[0].get("nickname") == action["new_name"]:
                return self.finish(owner, draft_id, existing["payload_hash"], action, "succeeded", f"nickname-{draft_id[:12]}", "")
        return Execution(status="not_found")
