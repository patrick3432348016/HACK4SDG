"""Synthetic weather fixtures: verify geography, dates, freshness and failure handling."""
from copy import deepcopy
from datetime import date, datetime, timedelta
import unittest
import httpx
from assistant.weather import HKOWeather, WeatherQuery, HK, UNAVAILABLE

NOW = datetime(2026, 10, 12, 15, 0, tzinfo=HK)
AT = NOW.isoformat()
FIXTURES = {
    "rhrread": {"temperature": {"recordTime": AT, "data": [
        {"place": "打鼓嶺", "value": 27, "unit": "C"},
        {"place": "香港天文台", "value": 30, "unit": "C"}]},
        "rainfall": {"startTime": (NOW-timedelta(hours=1)).isoformat(), "endTime": AT,
                     "data": [{"place": "北區", "max": 0, "unit": "mm", "main": "FALSE"}]}},
    "flw": {"updateTime": AT, "forecastPeriod": "本港地區下午及今晚天氣預測", "forecastDesc": "天晴。部分時間有陽光。"},
    "fnd": {"updateTime": AT, "weatherForecast": [
        {"forecastDate": "20261013", "forecastWeather": "有幾陣雨。", "forecastMintemp": {"unit": "C", "value": 24},
         "forecastMaxtemp": {"unit": "C", "value": 29}},
        {"forecastDate": "20261014", "forecastWeather": "天晴。"}]},
    "warnsum": {},
}


class WeatherTests(unittest.IsolatedAsyncioTestCase):
    async def asyncSetUp(self):
        self.data = deepcopy(FIXTURES)
        self.calls = []
        def response(request):
            self.assertEqual(request.url.host, "data.weather.gov.hk")
            self.assertNotIn("authorization", request.headers)
            self.assertNotIn("x-api-key", request.headers)
            kind = request.url.params["dataType"]
            self.calls.append(kind)
            value = self.data[kind]
            if isinstance(value, Exception):
                raise value
            return httpx.Response(200, json=value)
        self.client = httpx.AsyncClient(transport=httpx.MockTransport(response))
        self.weather = HKOWeather(self.client, clock=lambda: NOW)

    async def asyncTearDown(self):
        await self.client.aclose()

    async def test_north_station_and_whole_hk_forecast_are_separate(self):
        result = await self.weather.answer(WeatherQuery())
        self.assertIn("打鼓嶺27度", result["text"])
        self.assertIn("全港预报参考", result["text"])
        self.assertNotIn("30度", result["text"])
        self.assertEqual(result["weather"]["forecast"]["scope"], "全港")
        self.assertEqual(result["weather"]["rainfall"]["max_mm"], 0)
        self.assertTrue(result["weather"]["warnings_available"])
        self.assertNotIn("适合", result["text"])
        await self.weather.answer(WeatherQuery())
        self.assertEqual(len(self.calls), 3)  # one-minute per-session cache

    async def test_tomorrow_uses_exact_date_and_never_current_temperature(self):
        result = await self.weather.answer(WeatherQuery(day=date(2026, 10, 13)))
        self.assertIn("10月13日", result["text"])
        self.assertIn("24至29度", result["text"])
        self.assertIn("有幾陣雨", result["text"])
        self.assertEqual(result["weather"]["observations"], [])
        self.assertNotIn("rhrread", self.calls)

    async def test_no_fanling_or_sheung_shui_reading_is_not_invented(self):
        result = await self.weather.answer(WeatherQuery(place="sheung_shui", hourly=True))
        self.assertIn("未有上水本地读数", result["text"])
        self.assertIn("未有北区指定时段预报", result["text"])
        self.assertNotIn("上水27", result["text"])

    async def test_stale_values_are_not_reported_as_live(self):
        self.data["rhrread"]["temperature"]["recordTime"] = (NOW-timedelta(hours=2)).isoformat()
        self.data["flw"]["updateTime"] = (NOW-timedelta(hours=7)).isoformat()
        result = await self.weather.answer(WeatherQuery())
        self.assertEqual(result["text"], UNAVAILABLE)
        self.assertEqual(result["weather"]["observations"], [])
        self.assertIsNone(result["weather"]["forecast"])

    async def test_source_failure_is_partial_not_fabricated(self):
        self.data["rhrread"] = httpx.ConnectError("synthetic")
        self.data["warnsum"] = httpx.ConnectError("synthetic")
        result = await self.weather.answer(WeatherQuery())
        self.assertIn("全港预报参考", result["text"])
        self.assertIn("最新警告暂时查唔到", result["text"])
        self.assertFalse(result["weather"]["warnings_available"])

    async def test_active_cancelled_expired_and_future_day_warnings(self):
        self.data["warnsum"] = {
            "WHOT": {"name": "酷熱天氣警告", "code": "WHOT", "actionCode": "ISSUE", "updateTime": AT},
            "WRAIN": {"name": "暴雨警告", "code": "WRAINR", "actionCode": "CANCEL", "updateTime": AT},
            "WTS": {"name": "雷暴警告", "code": "WTS", "actionCode": "EXTEND", "updateTime": AT,
                    "expireTime": (NOW-timedelta(minutes=1)).isoformat()}}
        result = await self.weather.answer(WeatherQuery(day=date(2026, 10, 13)))
        self.assertTrue(result["text"].startswith("而家生效嘅有酷熱天氣警告"))
        self.assertNotIn("暴雨警告", result["text"])
        self.assertNotIn("雷暴警告", result["text"])

    async def test_outside_region_or_date_makes_no_request(self):
        for query in [WeatherQuery(place="other"), WeatherQuery(day=date(2026, 10, 1)), WeatherQuery(day=date(2026, 10, 21))]:
            result = await self.weather.answer(query)
            self.assertIsNone(result["weather"]["forecast"])
        self.assertEqual(self.calls, [])

    async def test_malformed_data_missing_date_future_time_and_invalid_units(self):
        self.data["rhrread"]["temperature"]["data"][0]["unit"] = "F"
        self.data["warnsum"] = {"bad": {"name": "test"}}
        self.data["flw"]["updateTime"] = (NOW+timedelta(hours=1)).isoformat()
        result = await self.weather.answer(WeatherQuery())
        self.assertEqual(result["text"], UNAVAILABLE)
        self.assertFalse(result["weather"]["warnings_available"])
        result = await self.weather.answer(WeatherQuery(day=date(2026, 10, 15)))
        self.assertIsNone(result["weather"]["forecast"])

    async def test_malformed_http_json_is_unavailable(self):
        async with httpx.AsyncClient(transport=httpx.MockTransport(lambda r: httpx.Response(200, text="not json"))) as client:
            result = await HKOWeather(client).answer(WeatherQuery())
            self.assertEqual(result["text"], UNAVAILABLE)

