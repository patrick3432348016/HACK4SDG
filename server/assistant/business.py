from datetime import datetime, timedelta
import httpx
from pydantic import ValidationError
from .config import Settings
from .errors import AssistantError
from .models import Context, Execution
from .store import Store


def demo_context(now: datetime) -> Context:
    yesterday = (now.replace(day=1) - timedelta(days=1)).date()
    return Context.model_validate({
        "version": "demo-v1", "contacts": [
            {"id": "chan", "name": "陈伯", "aliases": ["陳伯", "老陈", "老陳"]},
            {"id": "chan-tai", "name": "陈太", "aliases": ["陳太"]},
            {"id": "lee", "name": "李姨", "aliases": ["李阿姨"]},
        ],
        "places": [
            {"id": "garden", "name": "测试·社区花园", "description": "虚构的社区花园集合点", "is_open": True,
             "self_walk_minutes": 8, "contact_walk_minutes": {"chan": 10, "chan-tai": 6, "lee": 12}, "shade_fraction": .8},
            {"id": "plaza", "name": "测试·广场", "description": "虚构的社区广场", "is_open": True,
             "self_walk_minutes": 4, "contact_walk_minutes": {"chan": 5, "chan-tai": 8, "lee": 3}, "shade_fraction": .2},
            {"id": "pavilion", "name": "测试·凉亭", "description": "虚构的有顶凉亭", "is_open": True,
             "self_walk_minutes": 14, "contact_walk_minutes": {"chan": 12, "chan-tai": 15, "lee": 10}, "shade_fraction": .95},
        ],
        "walks": [{"day": str(yesterday), "minutes": 30, "metres": 1500}],
        "walk_coverage": {"start": str(yesterday.replace(day=1)), "end_exclusive": str(now.date().replace(day=1))},
    })


class Business:
    def __init__(self, settings: Settings, client: httpx.AsyncClient, store: Store):
        self.settings, self.client, self.store = settings, client, store

    async def request(self, method, path, token, **kwargs):
        try:
            result = await self.client.request(method, self.settings.business_base_url.rstrip("/") + path,
                                               headers={"Authorization": "Bearer " + token, **kwargs.pop("headers", {})}, **kwargs)
        except httpx.HTTPError as exc:
            raise AssistantError("BUSINESS_UNAVAILABLE", "业务服务暂时不可用，请稍后重试。", 503) from exc
        if result.status_code in (401, 403):
            raise AssistantError("UNAUTHORIZED", "登录已失效或没有操作权限。", 401)
        if not result.is_success:
            raise AssistantError("BUSINESS_UNAVAILABLE", "业务服务未能完成请求。", 503)
        try:
            return result.json()
        except ValueError as exc:
            raise AssistantError("BUSINESS_INVALID", "业务服务返回了无效数据。", 502) from exc

    async def identity(self, token: str) -> str:
        import secrets
        if self.settings.mode == "demo":
            if not secrets.compare_digest(token, self.settings.demo_token):
                raise AssistantError("UNAUTHORIZED", "联调令牌不正确。", 401)
            return "demo-user"
        data = await self.request("GET", "/assistant/session", token)
        if not isinstance(data, dict) or not isinstance(data.get("user_id"), str) or not 1 <= len(data["user_id"]) <= 200:
            raise AssistantError("BUSINESS_INVALID", "业务登录信息无效。", 502)
        return data["user_id"]

    async def context(self, token, now, starts_at=None):
        if self.settings.mode == "demo":
            result = demo_context(now)
            for place in result.places:
                at = starts_at or now
                place.shade_valid_from = at - timedelta(minutes=1)
                place.shade_valid_until = at + timedelta(minutes=30)
                place.source = "虚构联调数据，不代表实际遮荫"
            return result
        data = await self.request("GET", "/assistant/context", token, params={"at": (starts_at or now).isoformat()})
        try:
            return Context.model_validate(data)
        except ValidationError as exc:
            raise AssistantError("BUSINESS_INVALID", "业务数据不符合接口约定。", 502) from exc

    async def execute(self, token, owner, draft_id, payload):
        if self.settings.mode == "demo":
            return Execution.model_validate(self.store.demo_execute(draft_id, owner, payload))
        # A must atomically enforce authorization, expected context version and idempotency.
        data = await self.request("POST", "/assistant/actions", token,
                                  headers={"Idempotency-Key": draft_id}, json={"operation_id": draft_id,
                                  "action": payload["action"], "expected_context_version": payload["expected_context_version"]})
        return self.parse_execution(data)

    async def reconcile(self, token, owner, draft_id):
        if self.settings.mode == "demo":
            return Execution.model_validate(self.store.demo_receipt(draft_id, owner))
        data = await self.request("GET", "/assistant/actions/" + draft_id, token)
        return self.parse_execution(data)

    @staticmethod
    def parse_execution(data):
        try:
            result = Execution.model_validate(data)
            if result.status == "succeeded" and not result.receipt_id:
                raise ValueError("A success must have a receipt")
            return result
        except (ValidationError, ValueError) as exc:
            raise AssistantError("BUSINESS_INVALID", "操作回执无效，请查询结果。", 502) from exc
