"""Public HKO observations and forecasts. No credentials or LLM-written weather facts."""
import asyncio
from datetime import date, datetime, timedelta, timezone
import math
import re
import time
from typing import Literal

import httpx
from pydantic import BaseModel, ConfigDict

HK = timezone(timedelta(hours=8))
API = "https://data.weather.gov.hk/weatherAPI/opendata/weather.php"
SOURCE = "https://www.hko.gov.hk/tc/index.html"
UNAVAILABLE = "暂时攞唔到有效嘅天文台天气资料，我唔会估天气。出发前请查看香港天文台最新天气同警告。"
SCOPE = "北区测站实况；预报为全港参考，并非北区逐小时预报。"
PLACES = {"north": "北區", "sheung_shui": "上水", "ta_kwu_ling": "打鼓嶺", "fanling": "粉嶺"}


class WeatherQuery(BaseModel):
    model_config = ConfigDict(extra="forbid")
    place: Literal["north", "sheung_shui", "ta_kwu_ling", "fanling", "other"] = "north"
    day: date | None = None
    hourly: bool = False


def stamp(value):
    try:
        parsed = datetime.fromisoformat(value)
        return parsed.astimezone(HK) if parsed.tzinfo else None
    except (ValueError, TypeError):
        return None


def fresh(value, now, hours):
    parsed = stamp(value)
    return parsed is not None and -300 <= (now - parsed).total_seconds() <= hours * 3600


def number(value, low, high):
    return type(value) in (int, float) and math.isfinite(value) and low <= value <= high


def clean(value, limit=1600):
    return value.strip() if isinstance(value, str) and 0 < len(value.strip()) <= limit and "<" not in value else ""


def short_forecast(text):
    # Complete source sentences only; keep the spoken answer short for older users.
    sentences = re.findall(r"[^。！？]+[。！？]?", text)
    result = ""
    for sentence in sentences:
        if len(result + sentence) > 90:
            break
        result += sentence
    return result or "详细预报请睇天气卡。"


class HKOWeather:
    def __init__(self, client, clock=None):
        self.client = client
        self.clock = clock or (lambda: datetime.now(HK))
        self.cache = {}

    async def fetch(self, kind):
        cached = self.cache.get(kind)
        if cached and time.monotonic() - cached[0] < 60:
            return cached[1]
        if self.client is None:
            return None
        try:
            async with asyncio.timeout(6):
                # Explicitly suppress any credentials on a shared HTTP client.
                async with self.client.stream("GET", API, params={"dataType": kind, "lang": "tc"},
                        headers={"Cache-Control": "no-cache"}, auth=None, timeout=5,
                        follow_redirects=False) as response:
                    response.raise_for_status()
                    if int(response.headers.get("Age", "0")) > 300:
                        return None
                    body = bytearray()
                    async for chunk in response.aiter_bytes():
                        body.extend(chunk)
                        if len(body) > 256000:
                            return None
                    import json
                    data = json.loads(body)
                    if not isinstance(data, dict):
                        return None
                    self.cache[kind] = (time.monotonic(), data)
                    return data
        except (httpx.HTTPError, TimeoutError, ValueError, OSError):
            return None

    async def answer(self, query):
        now = self.clock().astimezone(HK)
        target = query.day or now.date()
        card = {"source": "香港天文台", "source_url": SOURCE, "scope": SCOPE,
                "requested_place": PLACES.get(query.place, "北區以外"),
                "date": target.isoformat(), "checked_at": now.isoformat(),
                "observations": [], "rainfall": None, "forecast": None,
                "warnings": [], "warnings_available": False, "notes": []}
        def result(text):
            return {"text": text, "policy": "weather", "business": None, "weather": card}
        if query.place == "other":
            return result("而家天气功能只支援香港北区实况同全港预报参考。你想问北区边一日嘅天气？")
        if not 0 <= (target - now.date()).days <= 8:
            return result("而家只可以查今日同未来八日嘅预报，未支援历史天气或者更远日期。你想问边一日？")
        today = target == now.date()
        kinds = ["rhrread", "flw", "warnsum"] if today else ["fnd", "warnsum"]
        values = await asyncio.gather(*(self.fetch(kind) for kind in kinds))
        data = dict(zip(kinds, values))
        parts = []
        current = data.get("rhrread")
        if today and isinstance(current, dict):
            temperature = current.get("temperature")
            if isinstance(temperature, dict) and fresh(temperature.get("recordTime"), now, 1.5):
                rows = temperature.get("data", [])
                rows = rows if isinstance(rows, list) else []
                for station in ("上水", "打鼓嶺"):
                    row = next((r for r in rows if isinstance(r, dict) and r.get("place") == station), {})
                    if row.get("unit") == "C" and number(row.get("value"), -20, 60):
                        card["observations"].append({"station": station, "temperature_c": row["value"],
                                                     "recorded_at": temperature["recordTime"]})
            rain = current.get("rainfall")
            if isinstance(rain, dict) and fresh(rain.get("endTime"), now, 2):
                rows = rain.get("data", [])
                start, end = stamp(rain.get("startTime")), stamp(rain.get("endTime"))
                row = next((r for r in rows if isinstance(r, dict) and r.get("place") == "北區"), {}) if isinstance(rows, list) else {}
                if (start and end and 0 < (end-start).total_seconds() <= 7200 and row.get("main") != "TRUE"
                        and row.get("unit") == "mm" and number(row.get("max"), 0, 1000)):
                    card["rainfall"] = {"district": "北區", "max_mm": row["max"],
                                        "from": rain["startTime"], "to": rain["endTime"]}
        if today:
            observations = card["observations"]
            preferred = next((o for o in observations if o["station"] == PLACES[query.place]), None)
            selected = [preferred] if preferred else observations
            if selected:
                label = "北区测站参考" if query.place == "north" or not preferred else PLACES[query.place] + "测站"
                readings = "，".join(f'{o["station"]}{o["temperature_c"]:g}度' for o in selected)
                at = stamp(selected[0]["recorded_at"]).strftime("%H点%M分")
                parts.append(f"天文台{at}实况，{label}：{readings}。")
            else:
                card["notes"].append("北区测站气温缺失或超过90分钟，未当作当前气温。")
                parts.append("暂时攞唔到北区有效嘅测站气温。")
            if query.place != "north" and not preferred:
                card["notes"].append(f"没有{PLACES[query.place]}本地有效读数；其他北区测站仅供参考。")
                parts.append(f"未有{PLACES[query.place]}本地读数。")
        forecast = data.get("flw" if today else "fnd")
        if isinstance(forecast, dict) and fresh(forecast.get("updateTime"), now, 6 if today else 24):
            if today and clean(forecast.get("forecastDesc")) and clean(forecast.get("forecastPeriod")):
                card["forecast"] = {"scope": "全港", "period": forecast["forecastPeriod"],
                    "description": forecast["forecastDesc"], "updated_at": forecast["updateTime"]}
            elif not today:
                rows = forecast.get("weatherForecast", [])
                row = next((r for r in rows if isinstance(r, dict) and r.get("forecastDate") == target.strftime("%Y%m%d")), {}) if isinstance(rows, list) else {}
                if clean(row.get("forecastWeather")):
                    card["forecast"] = {"scope": "全港", "period": target.isoformat(),
                        "description": row["forecastWeather"], "updated_at": forecast["updateTime"]}
                    lo, hi = row.get("forecastMintemp"), row.get("forecastMaxtemp")
                    if (isinstance(lo, dict) and isinstance(hi, dict) and lo.get("unit") == hi.get("unit") == "C"
                            and number(lo.get("value"), -20, 60) and number(hi.get("value"), lo["value"], 60)):
                        card["forecast"].update(min_c=lo["value"], max_c=hi["value"])
        fc = card["forecast"]
        if fc:
            period = fc["period"] if today else f"{target.month}月{target.day}日"
            parts.append(f"全港预报参考，{period}：{short_forecast(fc['description'])}")
            if "min_c" in fc:
                parts.append(f"全港气温{fc['min_c']:g}至{fc['max_c']:g}度。")
        else:
            card["notes"].append("所问日期的预报未取得有效更新。")
            parts.append("暂时攞唔到呢个日期嘅有效预报。")
        warnings = data.get("warnsum")
        if isinstance(warnings, dict):
            card["warnings_available"] = True
            for warning in warnings.values():
                if not isinstance(warning, dict):
                    card["warnings_available"] = False
                    continue
                if warning.get("actionCode") == "CANCEL" or warning.get("code") == "CANCEL":
                    continue
                updated = stamp(warning.get("updateTime"))
                expires = stamp(warning.get("expireTime"))
                if (warning.get("actionCode") not in {"ISSUE", "REISSUE", "EXTEND", "UPDATE"}
                        or not updated or updated > now + timedelta(minutes=5)
                        or not clean(warning.get("name"), 100)
                        or ("expireTime" in warning and expires is None)):
                    card["warnings_available"] = False
                    continue
                if expires and expires <= now:
                    continue
                card["warnings"].append({"name": warning["name"], "code": warning.get("code"),
                                         "updated_at": warning["updateTime"]})
        if card["warnings"]:
            names = "、".join(w["name"] for w in card["warnings"][:2])
            more = "等警告" if len(card["warnings"]) > 2 else ""
            # Current warnings must never be described as forecasts for a future day.
            parts.insert(0, f"而家生效嘅有{names}{more}。出门前请先睇天文台警告详情。")
        if not card["warnings_available"]:
            parts.append("最新警告暂时查唔到，出门前请再确认。")
        if query.hourly:
            parts.insert(0, "呢度未有北区指定时段预报，只可以提供全港预报参考。")
        if not card["observations"] and not fc and not card["warnings"]:
            return result(UNAVAILABLE)
        return result("".join(parts))
