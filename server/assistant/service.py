from datetime import datetime, timedelta, timezone
import time
from .business import Business
from .errors import AssistantError
from .models import Command, Reply, Choice, Context, Place
from .providers import Providers
from .store import Store

HK = timezone(timedelta(hours=8))


def shade_at(place: Place, at: datetime):
    if (place.shade_fraction is not None and place.source and place.shade_valid_from
        and place.shade_valid_until and place.shade_valid_from <= at < place.shade_valid_until):
        return place.shade_fraction
    return None


def rank_places(context: Context, contact_id: str, command: Command):
    candidates = []
    for place in context.places:
        other = place.contact_walk_minutes.get(contact_id)
        if place.is_open is not True or place.self_walk_minutes is None or other is None:
            continue
        longest = max(place.self_walk_minutes, other)
        if longest > command.max_walk_minutes:
            continue
        shade = shade_at(place, command.starts_at)
        if command.prefer_shade and shade is None:
            continue
        key = ((-(shade or 0), longest) if command.prefer_shade else (longest, -(shade or 0)))
        candidates.append((key, place))
    return [place for _, place in sorted(candidates, key=lambda row: (*row[0], row[1].id))]


class Assistant:
    def __init__(self, settings, store: Store, business: Business, providers: Providers, clock=None):
        self.settings, self.store, self.business, self.providers = settings, store, business, providers
        self.clock = clock or (lambda: datetime.now(HK))

    def reply(self, session_id, command, status, message, **kwargs):
        return Reply(conversation_id=session_id, command=command, status=status, message=message,
                     speech_text=message, demo=self.settings.mode == "demo", **kwargs)

    async def turn(self, owner, token, request):
        session = self.store.session(request.conversation_id, owner)
        previous = Command.model_validate(session["payload"]["command"]) if session["payload"].get("command") else None
        previous_draft = session["payload"].get("draft_id")
        if previous_draft and self.store.draft(previous_draft, owner)["status"] != "pending":
            previous = None
        now = self.clock()
        command = await self.providers.interpret(request.text, previous, now, request.locale)
        # Model sees only last structured command, not contacts, location history or raw logs.
        selected = {}
        if (previous and previous.intent == command.intent == "invite"
                and previous.contact_query == command.contact_query):
            contact_id = session["payload"].get("selected", {}).get("contact")
            if contact_id:
                selected["contact"] = contact_id
        return await self.evaluate(session, owner, token, command, request.locale, now, selected)

    async def choose(self, owner, token, session_id, request):
        session = self.store.session(session_id, owner)
        payload = session["payload"]
        expected = "choose_" + request.kind
        if payload.get("status") != expected or request.value not in payload.get("allowed", []):
            raise AssistantError("INVALID_CHOICE", "该选项已失效，请根据最新结果重新选择。", 409)
        command = Command.model_validate(payload["command"])
        selected = dict(payload.get("selected", {}))
        selected[request.kind] = request.value
        return await self.evaluate(session, owner, token, command, payload["locale"], self.clock(), selected)

    async def evaluate(self, session, owner, token, cmd, locale, now, selected=None):
        selected = selected or {}
        en = locale == "en-US"  # 10-17 English: most cards render locally, but info, landmark and monthly-report messages display directly.

        def t(cmn, english):
            return english if en else cmn
        context = None
        action = None
        choices = []
        data = {}
        status = "info"
        message = t("可以说：约陈伯明天下午四点散步，遮荫优先，最多15分钟。也可以说：明天请假、改名为小明、今日一句、散步建议、生成月报。",
                    "You can say: invite Mr Chan for a walk tomorrow at 4 pm, shady, 15 minutes at most. "
                    "Or say: day off tomorrow, or monthly report.")
        if cmd.intent == "cancel":
            status, message = "cancelled", t("已取消待确认请求；没有撤回已经提交的业务操作。", "Cancelled. Nothing was sent.")
        elif cmd.intent == "daily":
            message = await self.providers.creative("daily", {}, locale)
        elif cmd.intent == "rename":
            if not cmd.new_name:
                status, message = "needs_input", t("你想改成什么昵称？", "What name would you like?")
            elif any(ord(c) < 32 for c in cmd.new_name):
                raise AssistantError("INVALID_NAME", "昵称不能包含控制字符。", 422)
            else:
                action = {"kind": "rename", "new_name": cmd.new_name}
                message = t(f"把你的昵称改为“{cmd.new_name}”？请核对后点击确认。", f"Change your name to \"{cmd.new_name}\"? Check, then tap Confirm.")
        elif cmd.intent == "leave":
            if not cmd.leave_date:
                status, message = "needs_input", t("请说明请假日期，例如：明天请假。", "Which day off? For example: day off tomorrow.")
            elif not now.date() <= cmd.leave_date <= (now + timedelta(days=30)).date():
                status, message = "needs_input", t("请提供今天起30天内的请假日期。", "Pick a day within the next 30 days.")
            else:
                action = {"kind": "leave", "date": cmd.leave_date.isoformat()}
                message = t(f"将 {cmd.leave_date.isoformat()} 标记为请假？请核对后点击确认。", f"Day off on {cmd.leave_date:%-d %B}? Check, then tap Confirm.")
        elif cmd.intent == "invite":
            context = await self.business.context(token, now, cmd.starts_at)
            contact = next((c for c in context.contacts if c.id == selected.get("contact")), None)
            if selected.get("contact") and contact is None:
                raise AssistantError("CONTACT_CHANGED", "原先选择的联系人已不可用，请重新选择联系人。不会自动替换成同名用户。", 409)
            if not contact:
                query = (cmd.contact_query or "").casefold()
                matches = [c for c in context.contacts if query and query in [s.casefold() for s in [c.name, *c.aliases]]]
                if len(matches) == 1:
                    contact = matches[0]
                else:
                    available = matches or context.contacts
                    choices = [Choice(id=c.id, label=c.name) for c in available]
                    status = "choose_contact" if choices else "needs_input"
                    message = (t("请选择要邀请的联系人。", "Who would you like to invite?") if choices
                               else t("还没有可邀请的联系人，请先在主 App 中建立联系人。", "No neighbours yet. Tap phones to add a neighbour first."))
            if contact:
                selected["contact"] = contact.id
                cmd.contact_query = contact.name
                if not cmd.starts_at or not now < cmd.starts_at <= now + timedelta(days=30):
                    status, message = "needs_input", t("请提供未来30天内明确的日期和时间，例如：明天下午四点。", "What day and time? For example: tomorrow 4 pm.")
                elif not cmd.max_walk_minutes:
                    status, message = "needs_input", t("双方最多接受步行多少分钟？例如：最多15分钟。", "How many minutes can you both walk? For example: 15 minutes.")
                else:
                    places = rank_places(context, contact.id, cmd)
                    if not places:
                        status, message = "needs_input", t("没有满足步行限制、开放情况及所需遮荫数据的地点。可调整步行上限或稍后重试；不会猜测缺失数据。",
                                                           "No place fits. Try walking a bit further, or another time.")
                    else:
                        def describe(place):
                            shade = shade_at(place, cmd.starts_at)
                            if en:
                                return (f"You walk {place.self_walk_minutes:g} min, {contact.name} {place.contact_walk_minutes[contact.id]:g} min. "
                                        + (f"{shade:.0%} shady here." if shade is not None else "Shade unknown."))
                            return (f"你步行 {place.self_walk_minutes:g} 分钟，{contact.name} {place.contact_walk_minutes[contact.id]:g} 分钟；"
                                    + (f"集合点遮荫 {shade:.0%}" if shade is not None else "集合点遮荫未知") + "，不代表沿途遮荫。")
                        chosen = next((p for p in places if p.id == selected.get("place")), None)
                        if selected.get("place") and chosen is None:
                            raise AssistantError("PLACE_CHANGED", "地点条件已变化，请重新选择。", 409)
                        if chosen:
                            action = {"kind": "invite", "contact_id": contact.id, "place_id": chosen.id, "starts_at": cmd.starts_at.isoformat(),
                                      "max_walk_minutes": cmd.max_walk_minutes, "prefer_shade": cmd.prefer_shade}
                            message = (f"Invite {contact.name} on {cmd.starts_at.astimezone(HK):%-d %B, %H:%M} at {chosen.name}? {describe(chosen)} "
                                       f"They still need to say yes.") if en else f"邀请{contact.name}于 {cmd.starts_at.astimezone(HK):%Y-%m-%d %H:%M} 在{chosen.name}集合？{describe(chosen)}确认后只发送邀请，仍需对方接受。"
                        else:
                            status, message = "choose_place", ("Where to meet? Pick a place." if en else "请选择集合地点。排序依据：" + ("遮荫优先，再比较双方步行时间。" if cmd.prefer_shade else "优先降低双方中较长的步行时间。"))
                            choices = [Choice(id=p.id, label=p.name, detail=describe(p)) for p in places[:10]]
                            data = {"ranking": "shade_then_max_walk" if cmd.prefer_shade else "max_walk_then_shade", "context_version": context.version}
        elif cmd.intent in {"advice", "monthly", "landmark"}:
            context = await self.business.context(token, now)
            if cmd.intent == "advice":
                weather = context.weather
                if weather is None or not timedelta(0) <= now - weather.observed_at <= timedelta(hours=2):
                    message = t("没有两小时内的有效天气数据，暂不判断当前是否适合外出。出发前请查看当地天气；集合点有遮荫不代表沿途有遮荫。",
                                "No fresh weather data, so I can't say if it's good to go out. Check the weather before you go.")
                    data = {"weather_available": False}
                else:
                    message = f"{weather.summary}。" + ("当前有户外天气警告，请先查看官方警告详情。" if weather.outdoor_warning else "可结合个人步行能力选择集合地点；本信息不保证天气或路线安全。")
                    if en:
                        message = f"{weather.summary}. " + ("There is a weather warning. Check it first." if weather.outdoor_warning else "Walk at your own pace.")
                    data = {"weather_available": True, "source": weather.source, "observed_at": weather.observed_at.isoformat()}
            elif cmd.intent == "monthly":
                end = now.date().replace(day=1)
                start = (end - timedelta(days=1)).replace(day=1)
                coverage = context.walk_coverage
                complete = coverage is not None and coverage.start <= start and coverage.end_exclusive >= end
                data = {"period_start": str(start), "period_end_exclusive": str(end), "report_available": complete}
                if not complete:
                    message = t(f"未取得覆盖{start:%Y年%m月}的完整活动记录，暂不能生成月报。数据缺失不代表没有散步。",
                                f"No full record for {start:%B %Y} yet, so no report. Missing data doesn't mean you didn't walk.")
                else:
                    walks = [w for w in context.walks if start <= w.day < end]
                    data.update({"walk_count": len(walks), "active_days": len({w.day for w in walks}),
                                 "minutes": sum(w.minutes for w in walks), "metres": sum(w.metres for w in walks)})
                    message = t(f"{start:%Y年%m月}记录：{data['walk_count']}次散步，{data['active_days']}个活跃日，"
                                f"共{data['minutes']}分钟、{data['metres']}米。仅统计已记录活动，不推算减排量或健康收益。",
                                f"{start:%B %Y}: {data['walk_count']} walks on {data['active_days']} days, "
                                f"{data['minutes']} minutes, {data['metres']} metres in total.")
            else:
                matches = [p for p in context.places if cmd.landmark_query and cmd.landmark_query in p.name]
                if len(matches) != 1:
                    status, message = "needs_input", t("请指明一个已知地标，例如：给社区花园起名。不会给不存在的地点编造资料。",
                                                       "Which landmark? Say a landmark name from the app.")
                    data = {"known_places": [p.name for p in context.places]}
                else:
                    nickname = await self.providers.creative("landmark", {"name": matches[0].name, "description": matches[0].description}, locale)
                    message = t(f"昵称候选：{nickname}。这不是官方名称，尚未保存。", f"Name idea: {nickname}. Not official, not saved yet.")
                    data = {"place_id": matches[0].id, "suggested_name": nickname}
        if action:
            context = context or await self.business.context(token, now, cmd.starts_at)
            action = {"action": action, "expected_context_version": context.version, "confirmation_text": message}
            status = "needs_confirmation"
            # Structured confirmation includes contact/place IDs and time so the App localizes its recap without parsing message text.
            data["action"] = action["action"]
        payload = {"command": cmd.model_dump(mode="json"), "locale": locale, "status": status,
                   "selected": selected, "allowed": [c.id for c in choices]}
        draft_id = self.store.save(session, owner, payload, action, self.settings.draft_ttl_seconds)
        if self.settings.mode == "demo":
            data["data_source"] = "虚构联调数据"
        return self.reply(session["id"], cmd, status, message, choices=choices, draft_id=draft_id, data=data)

    async def confirm(self, owner, token, draft_id):
        claimed = self.store.claim(draft_id, owner)
        draft = self.store.draft(draft_id, owner)
        if claimed:
            try:
                # Recheck the time after the user has read the confirmation card.
                at = draft["payload"]["action"].get("starts_at")
                if at and datetime.fromisoformat(at) <= self.clock():
                    self.store.finish(draft_id, "failed", {"message": "集合时间已过，请重新创建邀请。"})
                else:
                    result = await self.business.execute(token, owner, draft_id, draft["payload"])
                    self.record_result(draft_id, result)
            except Exception:
                self.store.finish(draft_id, "uncertain")
                # Do not retry a write after timeout, malformed response or process uncertainty.
        elif draft["status"] in {"executing", "uncertain"}:
            try:
                result = await self.business.reconcile(token, owner, draft_id)
                self.record_result(draft_id, result)
            except AssistantError:
                pass
        return self.draft_reply(owner, draft_id)

    def record_result(self, draft_id, result):
        status = {"succeeded": "committed", "rejected": "failed"}.get(result.status, "uncertain")
        self.store.finish(draft_id, status, result.model_dump())

    def draft_reply(self, owner, draft_id):
        draft = self.store.draft(draft_id, owner)
        receipt = draft["receipt"] or {}
        state = draft["status"]
        if state == "committed":
            status = "completed"
            kind = draft["payload"]["action"]["kind"]
            message = {"invite": "邀请已发送，等待对方接受。", "leave": "请假已登记。", "rename": "昵称已更新。"}[kind]
            if self.settings.mode == "demo":
                message = "测试操作已保存；没有发送真实邀请或修改真实账号。"
        elif state in {"executing", "uncertain"}:
            status, message = "uncertain", "操作结果尚未确认。请点击查询结果；不要重新创建相同操作。"
        elif state == "cancelled":
            status, message = "cancelled", "待确认操作已取消，没有提交。"
        elif state == "failed":
            status, message = "info", "操作未完成。请查看主 App 中的当前状态后重新发起。"
        else:
            if draft["expires"] < time.time():
                status, message = "info", "确认卡已过期，未提交操作。请重新提出请求。"
                state = "expired"
            else:
                status, message = "needs_confirmation", draft["payload"].get("confirmation_text", "该操作尚未提交，请重新查看请求。")
        return self.reply(draft["session_id"], Command(), status, message, draft_id=draft_id,
                          data={"operation_status": state, "receipt_id": receipt.get("receipt_id")})
