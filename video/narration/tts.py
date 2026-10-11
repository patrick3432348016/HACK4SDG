"""Generate English narration with Kokoro (local, Apache-2.0).

Usage (venv: ~/Desktop/HACK/voice-runtime/kokoro-venv):
  python tts.py samples            -> narration/samples/<voice>.wav (voice audition)
  python tts.py all [--voice V]    -> public/vo/<id>.wav + src/vo.json (durations, seconds)
  python tts.py one <id>           -> regenerate a single line
"""
import json
import sys
from pathlib import Path

import numpy as np
import soundfile as sf
from kokoro import KPipeline

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent
SR = 24000
SCRIPT = json.loads((HERE / "script.json").read_text())
SAMPLE_VOICES = ["af_heart", "bf_emma", "am_michael", "bm_george"]
SAMPLE_TEXT = SCRIPT["lines"][1]["text"] + " " + SCRIPT["lines"][7]["text"]

_pipes = {}


def pipe(voice):
    lang = "b" if voice.startswith("b") else "a"
    if lang not in _pipes:
        _pipes[lang] = KPipeline(lang_code=lang, repo_id="hexgrad/Kokoro-82M")
    return _pipes[lang]


def synth(text, voice, speed):
    parts = [np.asarray(a) for _, _, a in pipe(voice)(text, voice=voice, speed=speed)]
    audio = np.concatenate(parts)
    # trim leading/trailing near-silence so timing is tight
    idx = np.where(np.abs(audio) > 0.01)[0]
    if len(idx):
        audio = audio[max(0, idx[0] - 1200): idx[-1] + 2400]
    return audio


def main():
    mode = sys.argv[1] if len(sys.argv) > 1 else "all"
    voice = SCRIPT["voice"]
    if "--voice" in sys.argv:
        voice = sys.argv[sys.argv.index("--voice") + 1]
    speed = SCRIPT.get("speed", 1.0)
    if mode == "samples":
        out = HERE / "samples"
        out.mkdir(exist_ok=True)
        for v in SAMPLE_VOICES:
            sf.write(out / f"{v}.wav", synth(SAMPLE_TEXT, v, speed), SR)
            print("sample", v)
        return
    vo = ROOT / "public" / "vo"
    vo.mkdir(parents=True, exist_ok=True)
    timing_path = ROOT / "src" / "vo.json"
    timing = json.loads(timing_path.read_text()) if timing_path.exists() else {}
    ids = [sys.argv[2]] if mode == "one" else [l["id"] for l in SCRIPT["lines"]]
    for line in SCRIPT["lines"]:
        if line["id"] not in ids:
            continue
        audio = synth(line["text"], line.get("voice", voice), line.get("speed", speed))
        sf.write(vo / f"{line['id']}.wav", audio, SR)
        timing[line["id"]] = round(len(audio) / SR, 3)
        print(line["id"], timing[line["id"]])
    timing_path.write_text(json.dumps(timing, indent=1))
    print("total", round(sum(timing.values()), 1), "s")


if __name__ == "__main__":
    main()
