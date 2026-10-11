from dataclasses import dataclass
import os
from urllib.parse import urlparse


@dataclass(frozen=True)
class Settings:
    mode: str = "demo"
    database: str = "data/assistant.sqlite3"
    demo_token: str = "local-demo-only"
    azure_key: str = ""
    azure_stt_url: str = ""
    azure_tts_url: str = ""
    qwen_key: str = ""
    qwen_base_url: str = ""
    qwen_model: str = ""
    business_base_url: str = ""
    # 成员 A 加（2026-10-11）：街坊行嘅 Supabase 业务适配（mode="supabase"）同本地粤语播报（GPT-SoVITS）。
    supabase_url: str = ""
    supabase_key: str = ""
    tts_provider: str = "auto"          # auto | sovits | azure | none；auto = 有 SOVITS_ROOT 用 sovits，否则 Azure（配咗先）
    sovits_root: str = ""
    sovits_ref_wav: str = ""
    sovits_ref_text: str = ""
    sovits_device: str = "cpu"
    speech_cache_dir: str = "data/tts-cache"
    speech_lan_open: bool = True        # 局域网（无代理头）嘅来源唔使登录都可以用播报；经隧道 / 代理嚟嘅要登录
    log_speech_text: bool = False
    max_body_bytes: int = 2_000_000
    requests_per_minute: int = 60
    draft_ttl_seconds: int = 600

    @classmethod
    def from_env(cls):
        return cls(**{k: os.environ[env] for k, env in {
            "mode": "ASSISTANT_MODE", "database": "ASSISTANT_DATABASE",
            "demo_token": "DEMO_TOKEN", "azure_key": "AZURE_SPEECH_KEY",
            "azure_stt_url": "AZURE_STT_URL", "azure_tts_url": "AZURE_TTS_URL",
            "qwen_key": "QWEN_API_KEY", "qwen_base_url": "QWEN_BASE_URL",
            "qwen_model": "QWEN_MODEL", "business_base_url": "BUSINESS_BASE_URL",
            "supabase_url": "SUPABASE_URL", "supabase_key": "SUPABASE_ANON_KEY",
            "tts_provider": "TTS_PROVIDER", "sovits_root": "SOVITS_ROOT", "sovits_ref_wav": "SOVITS_REF_WAV",
            "sovits_ref_text": "SOVITS_REF_TEXT", "sovits_device": "SOVITS_DEVICE", "speech_cache_dir": "SPEECH_CACHE_DIR",
        }.items() if env in os.environ},
            **{k: os.environ[env].lower() in {"1", "true", "yes"} for k, env in {
                "speech_lan_open": "SPEECH_LAN_OPEN", "log_speech_text": "VOICE_LOG_TEXT"}.items() if env in os.environ})

    @property
    def speech_ready(self):
        return bool(self.azure_key and self.azure_stt_url and self.azure_tts_url)

    @property
    def tts(self):
        """实际用边个播报：sovits（本机粤语）/ azure / none。"""
        if self.tts_provider == "auto":
            return "sovits" if self.sovits_root else ("azure" if self.speech_ready else "none")
        return self.tts_provider

    @property
    def model_ready(self):
        return bool(self.qwen_key and self.qwen_base_url and self.qwen_model)

    def validate(self):
        if self.mode not in {"demo", "production", "supabase"}:
            raise ValueError("ASSISTANT_MODE must be demo, production or supabase")
        if self.tts_provider not in {"auto", "sovits", "azure", "none"}:
            raise ValueError("TTS_PROVIDER must be auto, sovits, azure or none")
        if self.tts == "sovits" and not (self.sovits_root and self.sovits_ref_wav and self.sovits_ref_text):
            raise ValueError("sovits needs SOVITS_ROOT, SOVITS_REF_WAV and SOVITS_REF_TEXT")
        if self.mode == "supabase" and not (self.supabase_url and self.supabase_key):
            raise ValueError("supabase mode needs SUPABASE_URL and SUPABASE_ANON_KEY; tokens are verified by Supabase, never self-reported")
        if not self.demo_token:
            raise ValueError("DEMO_TOKEN must not be empty")
        for url in (self.azure_stt_url, self.azure_tts_url, self.qwen_base_url, self.business_base_url, self.supabase_url):
            if url and (urlparse(url).scheme != "https" or not urlparse(url).hostname
                        or urlparse(url).username or urlparse(url).password
                        or urlparse(url).query or urlparse(url).fragment):
                raise ValueError("Provider and business URLs must be HTTPS URLs without credentials/query/fragment")
        if self.mode == "production" and not (self.speech_ready and self.model_ready and self.business_base_url):
            raise ValueError("Production requires Azure, Qwen and an authenticated business API; demo fallback is forbidden")
