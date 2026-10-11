"""本机粤语播报（成员 A 加，2026-10-11）：GPT-SoVITS 常驻内存，一句一句排队合成，边合成边传。

- 声音：GPT-SoVITS v2ProPlus 预训练模型 + CC0 Common Voice 粤语参考录音（common_voice_yue_31206624）克隆。
- 一次只合成一句（模型唔系线程安全）：一条工作线程 + 优先队列。App 当场要讲嘅句子（priority 0）排喺预热句子（priority 1）前面。
- 传输：WAV（PCM16 单声道）。边合成边传嘅流式响应 RIFF / data 长度写 0xFFFFFFFF（App 自己解析）；缓存档案写正确长度。
- 缓存：按（声音版本、语言、语速、文字）做 key。内存（最近 64 MB）+ 磁盘（data/tts-cache/*.wav）。同一句正在合成时，
  第二个请求直接跟住收，唔会合成两次。
- 测试用 FakeEngine（tests/test_sovits.py），唔使装 torch。
"""
from __future__ import annotations

import asyncio
from collections import OrderedDict
from dataclasses import dataclass, field
import hashlib
import itertools
import logging
import os
from pathlib import Path
import queue
import re
import struct
import threading
import time
from typing import AsyncIterator, Callable, Iterator, Protocol

log = logging.getLogger("assistant.tts")

SAMPLE_WIDTH = 2
STREAM_SIZE = 0xFFFFFFFF


def wav_header(sample_rate: int, data_bytes: int | None = None) -> bytes:
    """44 字节 PCM16 单声道 WAV 头。data_bytes=None：流式（长度未知）。"""
    size = STREAM_SIZE if data_bytes is None else data_bytes
    riff = STREAM_SIZE if data_bytes is None else 36 + data_bytes
    return (b"RIFF" + struct.pack("<I", riff) + b"WAVEfmt " + struct.pack("<IHHIIHH", 16, 1, 1, sample_rate,
            sample_rate * SAMPLE_WIDTH, SAMPLE_WIDTH, 16) + b"data" + struct.pack("<I", size))


def clean_text(text: str) -> str:
    """App 嘅句子 → 适合合成嘅文字：去引号同符号、换行当句号、压空格。"""
    s = text.replace("\n", "。")
    s = re.sub(r"[「」『』“”\"'《》〈〉【】()（）\[\]]", "", s)
    s = s.replace("·", "，").replace("…", "。").replace("～", "，").replace("~", "，")
    s = re.sub(r"\s+", " ", s).strip(" ，,")
    return s


class SynthesisFailed(Exception):
    """一段声音都未出就失败（模型出错 / 文字合成唔到）。"""


class Engine(Protocol):
    sample_rate: int

    def load(self) -> None: ...

    def stream(self, text: str, speed: float) -> Iterator[bytes]:
        """逐段返回 PCM16 小端字节（sample_rate 固定）。"""


class SovitsEngine:
    """真模型：GPT-SoVITS 仓库入面嘅 TTS_infer_pack。只喺 load() 先 import torch。"""

    sample_rate = 32000

    def __init__(self, root: str, ref_wav: str, ref_text: str, device: str = "cpu", version: str = "v2ProPlus"):
        self.root, self.ref_wav, self.device, self.version = root, os.path.abspath(ref_wav), device, version
        self.ref_text = Path(ref_text).read_text(encoding="utf-8").strip()
        self.tts = None

    def load(self):
        import sys
        root = os.path.abspath(self.root)
        os.chdir(root)   # 模型相对路径（GPT_SoVITS/pretrained_models/...）同 G2P 字典都按仓库根目录读
        for p in (root, os.path.join(root, "GPT_SoVITS")):
            if p not in sys.path:
                sys.path.insert(0, p)
        from TTS_infer_pack.TTS import TTS, TTS_Config  # noqa: E402  (只喺有模型嘅机器先 import)
        pm = "GPT_SoVITS/pretrained_models"
        cfg = TTS_Config({"custom": {
            "device": self.device, "is_half": False, "version": self.version,
            "t2s_weights_path": f"{pm}/s1v3.ckpt", "vits_weights_path": f"{pm}/v2Pro/s2G{self.version}.pth",
            "bert_base_path": f"{pm}/chinese-roberta-wwm-ext-large", "cnhuhbert_base_path": f"{pm}/chinese-hubert-base"}})
        self.tts = TTS(cfg)

    def stream(self, text, speed=1.0):
        import numpy as np
        request = {"text": text, "text_lang": "yue", "ref_audio_path": self.ref_wav, "prompt_text": self.ref_text,
                   "prompt_lang": "yue", "text_split_method": "cut5", "batch_size": 1, "parallel_infer": False,
                   "seed": 1234, "streaming_mode": True, "speed_factor": float(speed), "fragment_interval": 0.25}
        for sr, chunk in self.tts.run(request):
            if sr != self.sample_rate:
                # GPT-SoVITS 出错时会返回一段 16 kHz 静音：当失败处理，唔好将佢当成声音传出去。
                raise RuntimeError("synthesis failed")
            yield np.asarray(chunk, dtype=np.int16).tobytes()


@dataclass
class Job:
    key: str
    text: str
    speed: float
    chunks: list[bytes] = field(default_factory=list)
    done: bool = False
    failed: bool = False
    started: bool = False
    subscribers: list[tuple[asyncio.AbstractEventLoop, asyncio.Queue]] = field(default_factory=list)
    queued_at: float = field(default_factory=time.monotonic)
    first_chunk_at: float | None = None


class SpeechService:
    """一条工作线程排队合成；HTTP 层用 stream() 边收边传。"""

    def __init__(self, engine_factory: Callable[[], Engine], cache_dir: str, voice_id: str,
                 memory_bytes: int = 64_000_000, log_text: bool = False):
        self.engine_factory, self.voice_id, self.log_text = engine_factory, voice_id, log_text
        self.cache_dir = Path(cache_dir)
        self.cache_dir.mkdir(parents=True, exist_ok=True)
        self.memory: OrderedDict[str, bytes] = OrderedDict()
        self.memory_limit, self.memory_size = memory_bytes, 0
        self.jobs: dict[str, Job] = {}
        self.queue: queue.PriorityQueue = queue.PriorityQueue()
        self.counter = itertools.count()
        self.lock = threading.Lock()
        self.engine: Engine | None = None
        self.sample_rate: int | None = None
        self.ready = threading.Event()
        self.load_error: str | None = None
        self.thread: threading.Thread | None = None
        self.stats = {"hits": 0, "misses": 0, "synthesized": 0}

    # ── 生命周期 ──

    def start(self, warm_text: str | None = "你好。"):
        if self.thread:
            return
        self.thread = threading.Thread(target=self._run, args=(warm_text,), name="sovits", daemon=True)
        self.thread.start()

    def _run(self, warm_text):
        started = time.monotonic()
        try:
            engine = self.engine_factory()
            engine.load()
            self.engine, self.sample_rate = engine, engine.sample_rate
            if warm_text:
                for _ in engine.stream(warm_text, 1.0):
                    pass
            log.warning("tts ready voice=%s load+warm=%.1fs", self.voice_id, time.monotonic() - started)
        except Exception as exc:  # 模型装唔到：服务照开（助手照用），播报返回 503，App 用系统声音
            self.load_error = f"{type(exc).__name__}: {exc}"
            log.error("tts load failed: %s", self.load_error)
            self.ready.set()
            return
        self.ready.set()
        while True:
            _, _, job = self.queue.get()
            if job is None:
                return
            with self.lock:
                if job.started or job.done:
                    continue   # 同一句排咗两次（预热之后又当场要）：做一次就够
                job.started = True
            self._synthesize(job)

    def stop(self):
        if self.thread:
            self.queue.put((-1, next(self.counter), None))

    # ── 缓存 ──

    def key(self, text: str, locale: str, speed: float) -> str:
        raw = f"{self.voice_id}\n{locale}\n{speed:.2f}\n{clean_text(text)}"
        return hashlib.sha256(raw.encode("utf-8")).hexdigest()

    def cached(self, key: str) -> bytes | None:
        with self.lock:
            data = self.memory.get(key)
            if data is not None:
                self.memory.move_to_end(key)
                return data
        path = self.cache_dir / f"{key}.wav"
        if path.exists():
            data = path.read_bytes()
            self._remember(key, data)
            return data
        return None

    def _remember(self, key, data):
        with self.lock:
            if key in self.memory:
                return
            self.memory[key] = data
            self.memory_size += len(data)
            while self.memory_size > self.memory_limit and self.memory:
                _, old = self.memory.popitem(last=False)
                self.memory_size -= len(old)

    # ── 合成 ──

    def _synthesize(self, job: Job):
        t0 = time.monotonic()
        try:
            for pcm in self.engine.stream(clean_text(job.text), job.speed):
                if not pcm:
                    continue
                with self.lock:
                    if job.first_chunk_at is None:
                        job.first_chunk_at = time.monotonic()
                    job.chunks.append(pcm)
                    subs = list(job.subscribers)
                for loop, q in subs:
                    loop.call_soon_threadsafe(q.put_nowait, pcm)
            pcm_all = b"".join(job.chunks)
            data = wav_header(self.sample_rate, len(pcm_all)) + pcm_all
            tmp = self.cache_dir / f"{job.key}.tmp"
            tmp.write_bytes(data)
            tmp.replace(self.cache_dir / f"{job.key}.wav")
            self._remember(job.key, data)
            self.stats["synthesized"] += 1
            audio = len(pcm_all) / SAMPLE_WIDTH / self.sample_rate
            first = (job.first_chunk_at or time.monotonic()) - job.queued_at
            log.warning("tts synth key=%s chars=%d wait+first=%.2fs total=%.2fs audio=%.2fs%s", job.key[:10], len(job.text),
                        first, time.monotonic() - job.queued_at, audio, f" text={job.text!r}" if self.log_text else "")
        except Exception as exc:
            job.failed = True
            log.error("tts synth failed key=%s after %.1fs: %s", job.key[:10], time.monotonic() - t0, type(exc).__name__)
        finally:
            with self.lock:
                job.done = True
                subs = list(job.subscribers)
                self.jobs.pop(job.key, None)
            for loop, q in subs:
                loop.call_soon_threadsafe(q.put_nowait, None)

    def enqueue(self, text: str, locale: str = "zh-HK", speed: float = 1.0, priority: int = 0) -> tuple[str, Job | None]:
        """排队（或者认返正在做 / 已经缓存咗嘅）。返回 (key, job)；job=None 表示已有缓存。"""
        key = self.key(text, locale, speed)
        if self.cached(key) is not None:
            return key, None
        with self.lock:
            job = self.jobs.get(key)
            if job is None:
                job = self.jobs[key] = Job(key=key, text=text, speed=speed)
            if not job.started:
                # 同一句可以排多次（预热 → 当场要）：工作线程见到已开始 / 已完成就跳过
                self.queue.put((priority, next(self.counter), job))
        return key, job

    async def stream(self, text: str, locale: str = "zh-HK", speed: float = 1.0, priority: int = 0) -> tuple[bool, AsyncIterator[bytes]]:
        """返回 (cache_hit, 字节流)。字节流第一段系 WAV 头。"""
        key, job = self.enqueue(text, locale, speed, priority)
        if job is None:
            self.stats["hits"] += 1
            data = self.cached(key)
            log.warning("tts hit key=%s chars=%d bytes=%d%s", key[:10], len(text), len(data), f" text={text!r}" if self.log_text else "")

            async def whole():
                yield data
            return True, whole()
        self.stats["misses"] += 1
        loop = asyncio.get_running_loop()
        q: asyncio.Queue = asyncio.Queue()
        with self.lock:
            backlog = list(job.chunks)
            finished = job.done
            if not finished:
                job.subscribers.append((loop, q))

        async def chunks():
            for pcm in backlog:
                yield pcm
            if finished:
                return
            try:
                while True:
                    pcm = await q.get()
                    if pcm is None:
                        break
                    yield pcm
            finally:
                with self.lock:
                    if (loop, q) in job.subscribers:
                        job.subscribers.remove((loop, q))

        async def live():
            # 等到第一段声音先出 WAV 头：合成失败（一段声都冇）时 HTTP 层可以答 503，App 即刻转用系统声音。
            source = chunks()
            try:
                first = await source.__anext__()
            except StopAsyncIteration:
                raise SynthesisFailed() from None
            yield wav_header(self.sample_rate or 32000) + first
            async for pcm in source:
                yield pcm
        return False, live()

    @property
    def status(self) -> str:
        if self.load_error:
            return "failed"
        return "ready" if self.ready.is_set() and self.engine else "loading"
