"""A, 2026-10-12: adapt the App's HTTP assistant endpoint to B's VoicePolicy.

B's original policy used one in-memory object per web WebSocket and integration-oriented spoken wording.
The App uses HTTP requests with stored conversation_id state, preserving B's processing order:
1. Local safety/scope rules return fixed guidance or refusal without calling the model.
2. VoicePolicy.decide uses the same prompt and Decision schema to route topic, App commands and weather conditions.
3. Weather reads official HKO data; transport/greetings use fixed text; rankings/history direct users to actual App screens.
4. App actions use Assistant.evaluate with clarification, place choice, confirmation, idempotency and no automatic execution.
Reply drives localized App cards and controlled speech; data.policy identifies the category.
Since 10-17, Mandarin and English follow the same route as Cantonese using the multilingual policy prompt.
Use CMN/EN fixed text and HKO simplified/English data; the former direct Mandarin path failed to handle weather and safety questions.
"""
from types import SimpleNamespace

from .models import Command, Reply
from .voice_policy import CMN, DENIED, EMERGENCY, EN, HELP, TRAFFIC, VoicePolicy
from .weather import HKOWeather

# The App has actual rankings/history, so replace B's standalone not-connected wording.
BOARD = "排行榜喺下面「排行榜」嗰頁，睇到附近街坊連續行咗幾多日。"
HISTORY = "你嘅散步紀錄喺「今日」嗰頁。想睇上個月，可以講「出月報」。"
FIXED = {"deny": DENIED, "emergency": EMERGENCY, "traffic": TRAFFIC, "board": BOARD, "history": HISTORY, "help": HELP}
FIXED_EN = {**EN, "board": "The Leaderboard tab shows how many days in a row nearby neighbours have walked.",
            "history": "Your walks are on the Today tab. Say \"monthly report\" to see last month."}
FIXED_CMN = {**CMN, "board": "排行榜在下面「排行榜」那页，可以看到附近邻居连续走了多少天。",
             "history": "你的散步记录在「今天」那页。想看上个月，可以说「生成月报」。"}


class TurnPolicy:
    def __init__(self, settings, store, assistant, provider, weather=None):
        self.settings, self.store, self.assistant, self.provider = settings, store, assistant, provider
        self.weather = weather or HKOWeather(provider.client)

    async def turn(self, owner, token, request):
        fixed = {"en-US": FIXED_EN, "zh-CN": FIXED_CMN}.get(request.locale, FIXED)
        session = self.store.session(request.conversation_id, owner)
        payload = session["payload"]
        previous = Command.model_validate(payload["command"]) if payload.get("command") else None
        if payload.get("draft_id") and self.store.draft(payload["draft_id"], owner)["status"] != "pending":
            previous = None
        state = SimpleNamespace(provider=self.provider, previous=previous, previous_weather=payload.get("weather"))
        decision = await VoicePolicy.decide(state, request.text.strip())
        if decision.topic == "weather" or (decision.topic == "app" and decision.command.intent == "advice"):
            query = decision.weather.model_dump(mode="json")
            answer = await self.weather.answer(decision.weather, request.locale)
            return self.info(session, owner, "weather", answer["text"], {"weather": answer["weather"]}, weather=query,
                             locale=request.locale)
        if decision.topic in FIXED:
            return self.info(session, owner, decision.topic, fixed[decision.topic], locale=request.locale)
        selected = {}
        cmd = decision.command
        if previous and previous.intent == cmd.intent == "invite" and previous.contact_query == cmd.contact_query:
            contact = payload.get("selected", {}).get("contact")
            if contact:
                selected["contact"] = contact
        reply = await self.assistant.evaluate(session, owner, token, cmd, request.locale, self.assistant.clock(), selected)
        reply.data["policy"] = "app"
        return reply

    def info(self, session, owner, policy, text, data=None, weather=None, locale="zh-HK"):
        # Store weather query conditions for follow-ups through previous_weather.
        self.store.save(session, owner, {"locale": locale, "status": "info", "weather": weather, "policy": policy})
        return Reply(conversation_id=session["id"], status="info", message=text, speech_text=text, command=Command(),
                     data={"policy": policy, **(data or {})}, demo=self.settings.mode == "demo")
