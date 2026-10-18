# Hong Kong North District weather integration

> Historical integration note, 12 October 2026, for member B's original delivery. Its entry point is the Windows real-time assistant's `VoicePolicy.answer()`; the older iOS REST demo weather endpoint is unchanged. Reuse `assistant/weather.py` and the `weather` field of answer events. The integrated StreetWalk app is documented in [server/README.md](../../README.md).

## Sources and coverage

Use public GET endpoints from the [Hong Kong Observatory Open Data API documentation](https://www.hko.gov.hk/tc/weatherAPI/doc/files/HKO_Open_Data_API_Documentation.pdf), without an additional API key:

`https://data.weather.gov.hk/weatherAPI/opendata/weather.php?dataType=…&lang=tc`

| Dataset | Purpose | Coverage |
|---|---|---|
| `rhrread` | Observed temperature and rainfall interval | Available Sheung Shui/Ta Kwu Ling station readings; North District rainfall only |
| `flw` | Latest local forecast with its official validity period | Hong Kong-wide, not a North District-specific forecast |
| `fnd` | Requested day's forecast and high/low temperature | Hong Kong-wide, up to eight days beyond today |
| `warnsum` | Currently active warnings | Official warning coverage, with Observatory detail links |

Default to North District. If Sheung Shui/Fanling is explicitly requested but no matching station reading exists, state that limitation and clearly label any North District reference station. Do not substitute Observatory headquarters humidity/temperature as a North District observation.

This module has no North District hourly forecast. For a specified time, explain that limitation and provide only the applicable Hong Kong-wide forecast. Rainfall is the district's maximum recorded amount over a past interval; it does not predict whether rain will stop.

Example requests include today's North District weather, rain in Fanling tomorrow, the current temperature in Ta Kwu Ling, and rain at 4 pm the day after tomorrow. Original Cantonese utterances in tests remain unchanged.

## Facts and failure handling

- The model extracts only a bounded location/date/time request; it does not invent weather facts. Scope restrictions apply before weather handling.
- Interpret dates in Hong Kong time. Only an immediately following weather question can inherit the previous query.
- Fetch sources concurrently, with a six-second limit and 256 KB response cap per endpoint. Cache successful responses for 60 seconds within the current voice session. This is not a background warning monitor.
- Application freshness limits: temperature 90 minutes, rainfall end time two hours, local forecast six hours, nine-day forecast 24 hours. Reject timestamps over five minutes in the future. These are app policies, not Observatory guarantees.
- Do not display cancelled/expired warnings as active. In future-day queries, label warnings as active **now**. An endpoint failure or invalid response does not mean no warnings, and no warning does not guarantee a suitable walk.
- Cards show station, observation time, forecast publication time, Hong Kong query time, missing data, and official links. Speech uses complete short forecast sentences; detailed forecasts remain on the card.
- On partial failure, provide remaining valid information with an explicit gap. On complete failure, say valid data is unavailable. Do not substitute static examples or model guesses.

## Validation

From the original backend directory:

```sh
python -m unittest discover -s tests -p test_weather.py
```

Full backend and page-state checks:

```sh
python tools/verify_backend.py
node tools/test_voice_ui.cjs
```

With local configuration saved and provider usage authorized:

```sh
python tools/check_voice_roundtrip.py --weather
```

The round-trip check feeds synthesized Cantonese into ASR without opening the microphone or saving audio. It does not measure older residents' recognition accuracy or loudspeaker experience.
