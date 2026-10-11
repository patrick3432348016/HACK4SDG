"""Transcode raw simulator recordings and map script steps to video seconds.

python3 footage/prep.py [name ...]
  -> public/clips/<name>.mp4 (30 fps CFR, full res)
  -> src/clips.json  {name: {dur, ev: {"t=N step": seconds}}}
  -> footage/sheets/<name>.jpg contact sheet (one frame per second, timestamped)
"""
import json
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
RAW = ROOT / "footage" / "raw"
CLIPS = ROOT / "public" / "clips"
SHEETS = ROOT / "footage" / "sheets"
OUT = ROOT / "src" / "clips.json"
CLIPS.mkdir(parents=True, exist_ok=True)
SHEETS.mkdir(parents=True, exist_ok=True)


def dur(p):
    return float(subprocess.check_output(["ffprobe", "-v", "error", "-show_entries", "format=duration", "-of", "csv=p=0", str(p)]).decode())


def main():
    names = sys.argv[1:] or sorted(p.stem for p in RAW.glob("*.mov") if p.stat().st_size > 0)
    data = json.loads(OUT.read_text()) if OUT.exists() else {}
    for n in names:
        mov = RAW / f"{n}.mov"
        mp4 = CLIPS / f"{n}.mp4"
        subprocess.run(["ffmpeg", "-y", "-v", "error", "-i", str(mov), "-vf", "fps=30", "-c:v", "libx264", "-preset", "medium",
                        "-crf", "18", "-pix_fmt", "yuv420p", "-movflags", "+faststart", str(mp4)], check=True)
        start = float((RAW / f"{n}.start").read_text())
        ev = {}
        for line in (RAW / f"{n}.app.log").read_text().splitlines():
            m = re.match(r"([\d.]+) \[(\w+)\] (t=\S+ .*)", line)
            if m:
                ev[m.group(3)] = round(float(m.group(1)) - start, 2)
        d = dur(mp4)
        data[n] = {"dur": round(d, 2), "ev": ev}
        # contact sheet: 1 fps, 10 per row, labelled
        subprocess.run(["ffmpeg", "-y", "-v", "error", "-i", str(mp4), "-vf",
                        "fps=1,scale=180:-2,tile=10x" + str(int(d) // 10 + 1),
                        "-frames:v", "1", "-q:v", "4", str(SHEETS / f"{n}.jpg")], check=True)
        print(n, round(d, 1), "s", ev)
    OUT.write_text(json.dumps(data, indent=1, ensure_ascii=False))


if __name__ == "__main__":
    main()
