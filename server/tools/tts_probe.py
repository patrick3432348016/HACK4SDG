"""Measure first-audio and full-utterance latency and save WAV samples for listening review.

Usage: python3 server/tools/tts_probe.py [--url http://127.0.0.1:8765] [--out directory] sentence1 sentence2 ...
Standard library only; direct LAN/localhost use needs no login.
"""
import argparse
import json
from pathlib import Path
import time
import urllib.request

parser = argparse.ArgumentParser()
parser.add_argument("--url", default="http://127.0.0.1:8765")
parser.add_argument("--out", default=".")
parser.add_argument("sentences", nargs="*", default=["阿芳啱啱出咗門，應該喺大快活門口嗰邊。"])
args = parser.parse_args()

with urllib.request.urlopen(args.url.rstrip("/") + "/v1/voice", timeout=5) as r:
    print("voice:", json.load(r))
out = Path(args.out)
out.mkdir(parents=True, exist_ok=True)
for i, text in enumerate(args.sentences, 1):
    req = urllib.request.Request(args.url.rstrip("/") + "/v1/speech/synthesize", method="POST",
                                 data=json.dumps({"text": text, "locale": "zh-HK"}).encode(),
                                 headers={"Content-Type": "application/json"})
    t0 = time.monotonic()
    with urllib.request.urlopen(req, timeout=120) as r:
        cache = r.headers.get("X-TTS-Cache")
        first = r.read(4096)
        t_first = time.monotonic() - t0
        rest = r.read()
    total = time.monotonic() - t0
    data = first + rest
    audio = (len(data) - 44) / 2 / 32000
    path = out / f"probe_{i}.wav"
    # Replace unknown streaming lengths with correct values before saving WAV.
    import struct
    pcm = len(data) - 44
    path.write_bytes(data[:4] + struct.pack("<I", 36 + pcm) + data[8:40] + struct.pack("<I", pcm) + data[44:])
    print(f"{i} cache={cache} 首段 {t_first:.2f}s 全句 {total:.2f}s 音频 {audio:.1f}s → {path} | {text}")
