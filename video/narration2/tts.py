"""宣传片配音：用豆包（同 App 小何同一套）合成 WAV。
用法：python tts.py <out.wav> <locale zh-HK|en-US> <speaker 或 default> <speed> <text>
密钥读 voice-runtime/doubao.json（唔入 git）。"""
import sys, wave
sys.path.insert(0, "/Users/nmgb/Desktop/HACK/HACK4SDG/server")
from assistant.config import load_doubao
from assistant.doubao_speech import DoubaoEngine
out, locale, speaker, speed, text = sys.argv[1:6]
cfg = load_doubao("/Users/nmgb/Desktop/HACK/voice-runtime/doubao.json")
if speaker != "default":
    cfg = cfg.model_copy(update={"speaker": speaker, "speaker_en": speaker})
eng = DoubaoEngine(cfg); eng.load()
pcm = b"".join(eng.stream(text, float(speed), locale))
with wave.open(out, "wb") as w:
    w.setnchannels(1); w.setsampwidth(2); w.setframerate(eng.sample_rate); w.writeframes(pcm)
print(out, round(len(pcm) / 2 / eng.sample_rate, 2), "s")
