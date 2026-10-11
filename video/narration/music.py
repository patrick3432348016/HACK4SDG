"""Procedural music bed + paper swish SFX (no downloads, no licences).

python3 narration/music.py <seconds>  -> public/music.wav, public/swish.wav
Warm felt-piano arpeggios over a soft pad: C – G/B – Am – F, 84 bpm.
"""
import sys
import wave
from pathlib import Path

import numpy as np

SR = 44100
ROOT = Path(__file__).resolve().parent.parent
rng = np.random.default_rng(7)


def note_hz(n):  # MIDI → Hz
    return 440.0 * 2 ** ((n - 69) / 12)


def piano(n, dur, vel=0.5):
    t = np.arange(int(dur * SR)) / SR
    f = note_hz(n)
    tone = sum((0.6 ** k) * np.sin(2 * np.pi * f * (k + 1) * t * (1 + 0.0004 * k)) for k in range(5))
    env = np.minimum(1, t / 0.008) * np.exp(-t * (2.2 + n / 60))
    return vel * tone * env


def pad(ns, dur):
    t = np.arange(int(dur * SR)) / SR
    sig = sum(np.sin(2 * np.pi * note_hz(n) * t + 0.3 * np.sin(2 * np.pi * 0.2 * t)) for n in ns)
    env = np.minimum(1, t / 1.2) * np.minimum(1, (dur - t) / 1.2)
    return 0.05 * sig * env


def reverb(x, secs=2.2, mix=0.28):
    n = int(secs * SR)
    ir = rng.standard_normal(n) * np.exp(-np.arange(n) / SR * 3.2)
    ir /= np.abs(ir).sum() / 8
    wet = np.fft.irfft(np.fft.rfft(x, len(x) + n) * np.fft.rfft(ir, len(x) + n))[: len(x)]
    return (1 - mix) * x + mix * wet


def lowpass(x, a=0.18):
    y = np.empty_like(x)
    acc = 0.0
    for i, v in enumerate(x):  # fine for one-off generation
        acc += a * (v - acc)
        y[i] = acc
    return y


def write(path, x):
    x = np.clip(x, -1, 1)
    with wave.open(str(path), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes((x * 32767).astype(np.int16).tobytes())


def main():
    total = float(sys.argv[1]) if len(sys.argv) > 1 else 200
    beat = 60 / 84
    bar = beat * 4
    chords = [  # (bass, arpeggio notes, pad notes)
        (48, [60, 64, 67, 72, 67, 64, 67, 71], [60, 64, 67]),  # C
        (47, [59, 62, 67, 71, 67, 62, 67, 74], [59, 62, 67]),  # G/B
        (45, [57, 60, 64, 69, 64, 60, 64, 67], [57, 60, 64]),  # Am
        (41, [57, 60, 65, 69, 65, 60, 65, 72], [57, 60, 65]),  # F
    ]
    out = np.zeros(int((total + 4) * SR))
    t = 0.0
    k = 0
    while t < total:
        bass, arp, pd = chords[k % 4]
        i0 = int(t * SR)
        p = pad(pd, bar * 2)
        out[i0: i0 + len(p)] += p[: len(out) - i0]
        b = piano(bass, bar * 2, 0.35)
        out[i0: i0 + len(b)] += b[: len(out) - i0]
        for j in range(8):  # one arpeggio note per beat over two bars
            nt = t + j * beat + rng.uniform(-0.01, 0.01)
            s = piano(arp[j], 2.5, 0.16 + 0.05 * (j % 4 == 0))
            a = int(nt * SR)
            out[a: a + len(s)] += s[: max(0, len(out) - a)]
        t += bar * 2
        k += 1
    out = out[: int(total * SR)]
    out = reverb(out)
    fade = np.minimum(1, np.arange(len(out)) / (SR * 3)) * np.minimum(1, (len(out) - np.arange(len(out))) / (SR * 5))
    out *= fade
    out *= 0.5 / np.max(np.abs(out))
    write(ROOT / "public" / "music.wav", out)

    # paper swish: band-limited noise with a quick swell
    n = int(0.55 * SR)
    tt = np.arange(n) / SR
    noise = lowpass(rng.standard_normal(n), 0.35) - lowpass(rng.standard_normal(n), 0.02)
    env = np.sin(np.pi * np.minimum(1, tt / 0.55)) ** 2.5
    sw = noise * env
    sw *= 0.35 / np.max(np.abs(sw))
    write(ROOT / "public" / "swish.wav", sw)
    print("music", round(total, 1), "s; swish ok")


if __name__ == "__main__":
    main()
