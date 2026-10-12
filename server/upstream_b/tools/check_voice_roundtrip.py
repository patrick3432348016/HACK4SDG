"""Opt-in live provider check using synthetic speech; no microphone or audio files.

Requires the user's authorization for cloud usage and a saved local configuration.
Sends a synthesized App question as 16 kHz PCM, then waits for reply audio.
"""
import asyncio
import argparse
import audioop
from contextlib import suppress
import json
from pathlib import Path
import sys
import time
import httpx
from websockets.asyncio.client import connect

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "backend"))
from assistant.doubao import Doubao, DoubaoConfig


async def main(weather=False):
    base = "http://127.0.0.1:8765"
    async with httpx.AsyncClient(trust_env=False, timeout=30) as client:
        token = (await client.get(base + "/windows/session")).json()["token"]
        saved = (await client.get(base + "/windows/config", headers={"Authorization":"Bearer " + token})).json()["config"]
        if not saved:
            raise RuntimeError("Save local configuration first")
        provider = Doubao(DoubaoConfig.model_validate(saved), client)
        question = "北區今日天氣點呀？" if weather else "你好，你可以幫我做啲乜？"
        audio = b"".join([chunk async for chunk in provider.synthesize(question)])
        pcm, _ = audioop.ratecv(audio, 2, 1, 24000, 16000, None)
    events, chunks, answer, final_at = [], 0, False, None
    started = time.monotonic()
    async with asyncio.timeout(55):
        async with connect("ws://127.0.0.1:8765/windows/realtime", origin=base, proxy=None) as ws:
            await ws.send(json.dumps({"token":token, "config":saved}))
            async def stream():
                pos = 0
                while True:
                    await ws.send(pcm[pos:pos+6400].ljust(6400, b"\0"))
                    pos += 6400
                    await asyncio.sleep(.2)
            sender = None
            try:
                while True:
                    message = json.loads(await ws.recv())
                    kind = message["type"]
                    if kind not in events:
                        events.append(kind)
                    if kind == "ready":
                        sender = asyncio.create_task(stream())
                    elif kind == "transcript" and message.get("final"):
                        final_at = time.monotonic()
                        print(json.dumps({"stage":"recognized_synthetic_speech", "text":message["text"]}, ensure_ascii=True), flush=True)
                    elif kind == "answer":
                        answer = not weather or bool(message.get("weather", {}).get("forecast") or message.get("weather", {}).get("observations"))
                        print(json.dumps({"stage":"reply", "text":message["text"], "weather":message.get("weather"), "understanding_ms":message.get("understanding_ms")}, ensure_ascii=True), flush=True)
                    elif kind == "audio":
                        chunks += 1
                        if chunks == 1:
                            print(json.dumps({"stage":"first_audio", "seconds_after_final":round(time.monotonic()-final_at, 2) if final_at else None}), flush=True)
                    elif kind in ("turn_error", "error"):
                        print(json.dumps({"stage":"error", "code":message.get("code")}), flush=True)
                        break
                    elif kind == "answer_done":
                        break
            finally:
                if sender:
                    sender.cancel()
                    with suppress(asyncio.CancelledError):
                        await sender
                with suppress(Exception):
                    await ws.send(json.dumps({"type":"stop"}))
    success = bool(final_at and answer and chunks)
    print(json.dumps({"success":success,"events":events,"audio_chunks":chunks,"elapsed":round(time.monotonic()-started,2)}), flush=True)
    return success


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--weather", action="store_true", help="Test the live HKO weather voice path")
    args = parser.parse_args()
    try:
        ok = asyncio.run(main(args.weather))
    except Exception as exc:
        print(json.dumps({"success":False,"error_type":type(exc).__name__}))
        ok = False
    sys.exit(0 if ok else 1)
