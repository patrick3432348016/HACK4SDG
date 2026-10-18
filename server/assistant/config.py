from dataclasses import dataclass
from functools import cached_property
import os
from pathlib import Path
from urllib.parse import urlparse

# A, 2026-10-12: use Doubao Ark's OpenAI-compatible chat/completions for understanding when B's config supplies a key.
ARK_BASE_URL = "https://ark.cn-beijing.volces.com/api/v3"


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
    # A, 2026-10-11: Supabase business mode and local GPT-SoVITS Cantonese synthesis.
    supabase_url: str = ""
    supabase_key: str = ""
    tts_provider: str = "auto"          # auto | doubao | sovits | azure | none; auto prefers SOVITS_ROOT, then Doubao, then Azure.
    # A, 2026-10-12: runtime Doubao config contains speech/Ark keys, model and voice; keep runtime credentials outside Git.
    doubao_config: str = ""
    sovits_root: str = ""
    sovits_ref_wav: str = ""
    sovits_ref_text: str = ""
    sovits_device: str = "cpu"
    speech_cache_dir: str = "data/tts-cache"
    speech_lan_open: bool = True        # Direct LAN requests without proxy headers may synthesize anonymously; tunnel/proxy requests require login.
    log_speech_text: bool = False
    max_body_bytes: int = 2_000_000
    requests_per_minute: int = 60
    draft_ttl_seconds: int = 600

    @classmethod
    def from_env(cls):
        values = cls._env_values()
        # Use Doubao Ark when configured unless Qwen is explicitly configured separately.
        if values.get("doubao_config") and "qwen_key" not in values:
            doubao = load_doubao(values["doubao_config"])
            values.update(qwen_key=doubao.ark_key.get_secret_value(), qwen_base_url=ARK_BASE_URL, qwen_model=doubao.model)
        return cls(**values)

    @classmethod
    def _env_values(cls):
        return dict(**{k: os.environ[env] for k, env in {
            "mode": "ASSISTANT_MODE", "database": "ASSISTANT_DATABASE",
            "demo_token": "DEMO_TOKEN", "azure_key": "AZURE_SPEECH_KEY",
            "azure_stt_url": "AZURE_STT_URL", "azure_tts_url": "AZURE_TTS_URL",
            "qwen_key": "QWEN_API_KEY", "qwen_base_url": "QWEN_BASE_URL",
            "qwen_model": "QWEN_MODEL", "business_base_url": "BUSINESS_BASE_URL",
            "supabase_url": "SUPABASE_URL", "supabase_key": "SUPABASE_ANON_KEY",
            "tts_provider": "TTS_PROVIDER", "sovits_root": "SOVITS_ROOT", "sovits_ref_wav": "SOVITS_REF_WAV",
            "sovits_ref_text": "SOVITS_REF_TEXT", "sovits_device": "SOVITS_DEVICE", "speech_cache_dir": "SPEECH_CACHE_DIR",
            "doubao_config": "DOUBAO_CONFIG",
        }.items() if env in os.environ},
            **{k: os.environ[env].lower() in {"1", "true", "yes"} for k, env in {
                "speech_lan_open": "SPEECH_LAN_OPEN", "log_speech_text": "VOICE_LOG_TEXT"}.items() if env in os.environ})

    @property
    def transcription_ready(self):
        return bool(self.azure_key and self.azure_stt_url)

    @property
    def speech_ready(self):
        return bool(self.azure_key and self.azure_stt_url and self.azure_tts_url)

    @cached_property
    def doubao(self):
        """DoubaoConfig, or None without DOUBAO_CONFIG."""
        return load_doubao(self.doubao_config) if self.doubao_config else None

    @property
    def tts(self):
        """Resolved synthesis provider: doubao, sovits, azure or none."""
        if self.tts_provider == "auto":
            return ("sovits" if self.sovits_root else "doubao" if self.doubao_config
                    else "azure" if self.speech_ready else "none")
        return self.tts_provider

    @property
    def model_ready(self):
        return bool(self.qwen_key and self.qwen_base_url and self.qwen_model)

    def validate(self):
        if self.mode not in {"demo", "production", "supabase"}:
            raise ValueError("ASSISTANT_MODE must be demo, production or supabase")
        if self.tts_provider not in {"auto", "doubao", "sovits", "azure", "none"}:
            raise ValueError("TTS_PROVIDER must be auto, doubao, sovits, azure or none")
        if self.tts == "doubao" and self.doubao is None:
            raise ValueError("doubao needs DOUBAO_CONFIG (B's voice-config.json)")
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


def load_doubao(path):
    """Read and validate B's config below 12 KB, as in its macOS/server.py."""
    from .doubao import DoubaoConfig
    file = Path(path).expanduser()
    if file.stat().st_size > 12000:
        raise ValueError("DOUBAO_CONFIG too large")
    return DoubaoConfig.model_validate_json(file.read_bytes())
