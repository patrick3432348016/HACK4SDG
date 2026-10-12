"""成员 A 加（2026-10-12）：App 嘅 /v1/assistant/turn 换成 B 新版嗰套（voice_policy.py）。

B 嘅 VoicePolicy 系为佢 Mac 网页实时对话写嘅：一个 WebSocket 一个对象、状态喺内存、播报用联调字眼。
App 用 HTTP，每句一个请求、对话状态喺 store（conversation_id），所以呢度照 B 嘅次序做：
1. B 嘅本地规则：紧急求助 → 固定求助提示；医疗 / 投资 / 政治 / 色情 → 固定拒答（唔问模型）；
2. B 嘅豆包路由（直接用 VoicePolicy.decide，同一个提示、同一个 Decision 结构）：话题 + App 指令 + 天气查询条件；
3. 天气 → B 嘅天文台（weather.py，只读官方数据，唔估）；交通 / 打招呼 → B 嘅固定句；排行榜 / 散步纪录 App 自己有，讲去边度睇；
4. App 操作 → B 嘅 Assistant.evaluate（问时间、揀地点、确认卡、幂等、唔准自动执行，全部不变）。
App 收到 Reply 照旧出自己嘅粤语卡、自己讲（唔会读模型写嘅字）；data.policy 话俾 App 知系边类。
普通话界面（zh-CN）：B 嘅路由同固定句都系粤语，照旧用 Assistant.turn（豆包只抽指令）。
"""
from types import SimpleNamespace

from .models import Command, Reply
from .voice_policy import DENIED, EMERGENCY, HELP, TRAFFIC, VoicePolicy
from .weather import HKOWeather

# App 入面有真排行榜同散步纪录（B 嘅 BOARD / HISTORY 讲「未接通」，喺 App 唔啱）。
BOARD = "排行榜喺下面「排行榜」嗰頁，睇到附近街坊連續行咗幾多日。"
HISTORY = "你嘅散步紀錄喺「今日」嗰頁。想睇上個月，可以講「出月報」。"
FIXED = {"deny": DENIED, "emergency": EMERGENCY, "traffic": TRAFFIC, "board": BOARD, "history": HISTORY, "help": HELP}


class TurnPolicy:
    def __init__(self, settings, store, assistant, provider, weather=None):
        self.settings, self.store, self.assistant, self.provider = settings, store, assistant, provider
        self.weather = weather or HKOWeather(provider.client)

    async def turn(self, owner, token, request):
        if request.locale != "zh-HK":
            return await self.assistant.turn(owner, token, request)
        session = self.store.session(request.conversation_id, owner)
        payload = session["payload"]
        previous = Command.model_validate(payload["command"]) if payload.get("command") else None
        if payload.get("draft_id") and self.store.draft(payload["draft_id"], owner)["status"] != "pending":
            previous = None
        state = SimpleNamespace(provider=self.provider, previous=previous, previous_weather=payload.get("weather"))
        decision = await VoicePolicy.decide(state, request.text.strip())
        if decision.topic == "weather" or (decision.topic == "app" and decision.command.intent == "advice"):
            query = decision.weather.model_dump(mode="json")
            answer = await self.weather.answer(decision.weather)
            return self.info(session, owner, "weather", answer["text"], {"weather": answer["weather"]}, weather=query)
        if decision.topic in FIXED:
            return self.info(session, owner, decision.topic, FIXED[decision.topic])
        selected = {}
        cmd = decision.command
        if previous and previous.intent == cmd.intent == "invite" and previous.contact_query == cmd.contact_query:
            contact = payload.get("selected", {}).get("contact")
            if contact:
                selected["contact"] = contact
        reply = await self.assistant.evaluate(session, owner, token, cmd, request.locale, self.assistant.clock(), selected)
        reply.data["policy"] = "app"
        return reply

    def info(self, session, owner, policy, text, data=None, weather=None):
        # 记低天气查询条件：紧接住问「咁聽日呢」时 B 嘅路由会参考（previous_weather）。
        self.store.save(session, owner, {"locale": "zh-HK", "status": "info", "weather": weather, "policy": policy})
        return Reply(conversation_id=session["id"], status="info", message=text, speech_text=text, command=Command(),
                     data={"policy": policy, **(data or {})}, demo=self.settings.mode == "demo")
