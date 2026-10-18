"""Live three-language provider checks call real Doubao; the non-test filename excludes them from unittest discovery.

Start a demo server with fictional business contacts; credentials are read only server-side while routing, Doubao and HKO remain real.
    cd server && ASSISTANT_MODE=demo DOUBAO_CONFIG=~/Desktop/HACK/voice-runtime/doubao.json TTS_PROVIDER=doubao \\
        ASSISTANT_DATABASE=/tmp/live3.sqlite3 SPEECH_CACHE_DIR=/tmp/live3-tts \\
        ~/Desktop/HACK/voice-runtime/venv/bin/python -m assistant.serve assistant.app:create_app --factory --port 8799
Then run:
    ~/Desktop/HACK/voice-runtime/venv/bin/python server/tests/live_three_lang.py --server http://127.0.0.1:8799

Three checks:
1. macOS say generates Cantonese/Mandarin/English invitation, weather and emergency samples; ffmpeg converts to 16 kHz mono PCM16.
   Stream them to /v1/voice/ear using the App protocol and inspect recognized text.
2. Send six requests per language for invitation, weather, leave, safety and confirmation; inspect intent/policy and reply language.
3. Synthesize one Xiaohe sample per language, save under docs/voice_samples/three_lang, then transcribe it again.
"""
import argparse
import asyncio
import json
from pathlib import Path
import re
import subprocess
import sys
import tempfile
import time

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import assistant.compat  # noqa: E402,F401  Load Python 3.10 asyncio.timeout compatibility before websockets.
import httpx  # noqa: E402
from websockets.asyncio.client import connect  # noqa: E402

ROOT = Path(__file__).resolve().parents[2]
SAMPLES = ROOT / "docs" / "voice_samples" / "three_lang"
VOICES = {"zh-HK": "Sinji", "zh-CN": "Tingting", "en-US": "Samantha"}
NAMES = {"zh-HK": "yue", "zh-CN": "cmn", "en-US": "en"}

# Input text and acceptable recognized keywords, matching any one.
EAR = {
    "zh-HK": [("約陳伯聽日下晝三點十五分散步，行四十分鐘。", ["陈伯", "陳伯"]), ("聽日天氣點呀？", ["天气", "天氣"]),
              ("救命呀，我跌親起唔到身。", ["救命"])],
    "zh-CN": [("约陈伯明天下午三点十五分散步，走四十分钟。", ["陈伯"]), ("明天天气怎么样？", ["天气"]),
              ("救命，我摔倒了起不来。", ["救命"])],
    "en-US": [("Invite Mr Chan for a walk tomorrow at 3:15 pm, for 40 minutes.", ["walk"]),
              ("What's the weather like tomorrow?", ["weather"]), ("Help! I fell down and I can't get up.", ["help", "fell"])],
}
# Input text and expected intent or policy.
TURN = {
    "zh-HK": [("約陳伯聽日下晝三點十五分散步，行四十分鐘", "invite"), ("聽日天氣點呀", "weather"), ("聽日請假", "leave"),
              ("救命，有人暈倒", "emergency"), ("呢隻藥食幾多粒", "deny"), ("好", "help")],
    "zh-CN": [("约陈伯明天下午三点十五分散步，走四十分钟", "invite"), ("明天天气怎么样", "weather"), ("明天请假", "leave"),
              ("救命，有人晕倒了", "emergency"), ("这个药吃几粒", "deny"), ("好", "help"),
              # 10-18: duration must not become clock minutes; the requested time is 15:00.
              ("约陈伯明天下午3点散步40分钟", "invite"), ("约陈伯明天下午三点散步四十分钟", "invite"), ("约陈伯明天下午3点走半个钟", "invite")],
    "en-US": [("Invite Mr Chan for a walk tomorrow at 3:15 pm for 40 minutes", "invite"), ("What's the weather like tomorrow?", "weather"),
              ("I want a day off tomorrow", "leave"), ("Help! Someone has collapsed", "emergency"),
              ("How many pills of this medicine should I take?", "deny"), ("Yes", "help")],
}
SPEAK = {"zh-HK": "聽日朝早八點，約陳伯喺花園一齊行。", "zh-CN": "明天早上八点，约陈伯在花园一起走。",
         "en-US": "Tomorrow 8 am, invite Mr Chan for a walk in the garden."}


def pcm16k(path):
    return subprocess.run(["ffmpeg", "-loglevel", "error", "-i", str(path), "-ac", "1", "-ar", "16000", "-f", "s16le", "-"],
                          capture_output=True, check=True).stdout


def say(text, voice, out):
    subprocess.run(["say", "-v", voice, "-o", str(out), text], check=True)
    return pcm16k(out)


def lang_of(text):
    """Reply language classification: en, yue with Cantonese markers, or zh when Chinese variants are indistinguishable."""
    if not re.search(r"[一-鿿]", text):
        return "en"
    return "yue" if re.search(r"[嘅唔咗喺嚟攞乜冇嗰啲咁]", text) else "zh"


async def ear(server, locale, pcm):
    """Send 200 ms audio chunks at roughly twice real time; return the first final transcript and delay after the last chunk."""
    url = server.replace("http", "ws", 1) + "/v1/voice/ear"
    pcm += b"\0" * 16000 * 2 * 2   # Append two seconds of silence for utterance finalization.
    async with connect(url, open_timeout=10, proxy=None) as ws:
        await ws.send(json.dumps({"locale": locale}))
        hello = json.loads(await asyncio.wait_for(ws.recv(), 10))
        if hello.get("type") != "ready":
            return f"<{hello.get('code')}: {hello.get('message')}>", 0
        speech_end = [None]

        async def feed():
            for i in range(0, len(pcm), 6400):
                await ws.send(pcm[i:i + 6400])
                if i + 6400 >= len(pcm) - 64000 and speech_end[0] is None:
                    speech_end[0] = time.monotonic()
                await asyncio.sleep(0.1)
        task = asyncio.create_task(feed())
        text = ""
        try:
            async with asyncio.timeout(30):
                async for message in ws:
                    event = json.loads(message)
                    if event.get("type") == "error":
                        text = f"<{event.get('code')}>"
                        break
                    if event.get("type") == "transcript" and event.get("final"):
                        text = event["text"]
                        break
        except TimeoutError:
            text = "<timeout>"
        took = time.monotonic() - (speech_end[0] or time.monotonic())
        task.cancel()
        await ws.send(json.dumps({"type": "stop"}))
        return text, took


async def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--server", default="http://127.0.0.1:8799")
    parser.add_argument("--token", default="local-demo-only")
    args = parser.parse_args()
    rows, failures = [], 0
    work = Path(tempfile.mkdtemp(prefix="live3-"))
    SAMPLES.mkdir(parents=True, exist_ok=True)
    async with httpx.AsyncClient(timeout=40) as client:
        print("== 1. 识别（/v1/voice/ear）")
        for locale, items in EAR.items():
            for n, (text, keys) in enumerate(items):
                heard, took = await ear(args.server, locale, say(text, VOICES[locale], work / f"{NAMES[locale]}{n}.aiff"))
                ok = any(k.lower() in heard.lower() for k in keys)
                failures += not ok
                print(f"[{'OK' if ok else 'FAIL'}] {locale} 讲：{text} → 认成：{heard}（讲完到出字 {took:.1f}s）")
        print("== 2. 理解（/v1/assistant/turn）")
        for locale, items in TURN.items():
            for text, expect in items:
                started = time.monotonic()
                r = await client.post(args.server + "/v1/assistant/turn", json={"text": text, "locale": locale},
                                      headers={"Authorization": "Bearer " + args.token})
                took = time.monotonic() - started
                body = r.json()
                if r.status_code != 200:
                    failures += 1
                    print(f"[FAIL] {locale} {text} → HTTP {r.status_code} {body}")
                    continue
                policy, intent = body["data"].get("policy"), body["command"]["intent"]
                got = intent if policy in (None, "app") else policy
                lang = lang_of(body["message"])
                want_lang = {"en-US": "en", "zh-CN": "zh"}.get(locale, "yue")
                ok = got in expect.split("|") and (lang in want_lang.split("|") or policy in (None, "app"))
                failures += not ok
                cmd = body["command"]
                extra = f" 时间={cmd.get('starts_at')} 分钟={cmd.get('max_walk_minutes')} 人={cmd.get('contact_query')}" if intent == "invite" else ""
                print(f"[{'OK' if ok else 'FAIL'}] {locale} 讲：{text} → {got}（{body['status']}）{extra} 回复[{lang}]：{body['message'][:110]}（{took:.1f}s）")
        print("== 3. 播报（/v1/speech/synthesize，小何）+ 识别回认")
        for locale, text in SPEAK.items():
            started = time.monotonic()
            r = await client.post(args.server + "/v1/speech/synthesize", json={"text": text, "locale": locale})
            took = time.monotonic() - started
            if r.status_code != 200:
                failures += 1
                print(f"[FAIL] {locale} 播报 HTTP {r.status_code} {r.text[:200]}")
                continue
            wav = work / f"{NAMES[locale]}.wav"
            wav.write_bytes(r.content)
            mp3 = SAMPLES / f"{NAMES[locale]}.mp3"
            subprocess.run(["ffmpeg", "-loglevel", "error", "-y", "-i", str(wav), "-ac", "1", "-b:a", "64k", str(mp3)], check=True)
            heard, _ = await ear(args.server, locale, pcm16k(wav))
            key = {"zh-HK": "陈伯", "zh-CN": "陈伯", "en-US": "walk"}[locale]
            ok = key in heard.replace("陳", "陈").lower() or (locale == "en-US" and "garden" in heard.lower())
            failures += not ok
            print(f"[{'OK' if ok else 'FAIL'}] {locale} 播：{text} → 回认：{heard}（合成 {took:.1f}s，{r.headers.get('X-Voice-ID')}）→ {mp3.relative_to(ROOT)}")
    print(f"== 完：{'全部通过' if not failures else f'{failures} 项唔啱'}")
    return failures


if __name__ == "__main__":
    raise SystemExit(1 if asyncio.run(main()) else 0)
