#!/bin/sh
# 街坊行 · Mac 语音服务器（组员 B 嘅豆包那套：识别 + 理解 + 小何粤语声；加 App 嘅 Supabase 业务）。一条命令开：
#   tools/voice_server.sh             # 局域网：同一个 Wi-Fi 嘅 iPhone 自动搵到（Bonjour _jiefongvoice._tcp）
#   tools/voice_server.sh --tunnel    # 再开 Cloudflare 临时公网地址（https://….trycloudflare.com，唔使账号）
#   tools/voice_server.sh --verbose   # 日志印埋合成嘅句子（排查用）
#   tools/voice_server.sh --test      # 只跑服务器测试
#   tools/voice_server.sh --voice=sovits  # 播报改返 Mac 本机 GPT-SoVITS 真人声（要声音模型；默认豆包小何）
# Python 环境同 B 嘅豆包配置（doubao.json，有密钥）喺仓库外面：$VOICE_RUNTIME（默认 ~/Desktop/HACK/voice-runtime，见 server/README.md）。
# 部 Mac 要保持开机唔好瞓（脚本会用 caffeinate 防止闲置瞓眠；合埋盖照样会瞓）。Ctrl-C 停。
set -e
cd "$(dirname "$0")/.."
REPO=$(pwd)
RUNTIME=${VOICE_RUNTIME:-$HOME/Desktop/HACK/voice-runtime}
PY="$RUNTIME/venv/bin/python"
PORT=${PORT:-8765}
TUNNEL=0
TESTONLY=0
VOICE=${TTS_PROVIDER:-doubao}
for a in "$@"; do
  case "$a" in
    --tunnel) TUNNEL=1 ;;
    --verbose) export VOICE_LOG_TEXT=1 ;;
    --test) TESTONLY=1 ;;
    --port=*) PORT=${a#--port=} ;;
    --voice=*) VOICE=${a#--voice=} ;;
    *) echo "唔识呢个参数：$a"; exit 2 ;;
  esac
done
if [ ! -x "$PY" ]; then
  # 第一次用（例如组员部 Mac）：建一个细嘅 Python 环境（豆包喺云端，唔使声音模型），约 1 分钟，要网络
  echo "第一次用：建 Python 环境（$RUNTIME/venv）…"
  mkdir -p "$RUNTIME"
  if command -v uv >/dev/null 2>&1; then
    uv venv --python 3.12 "$RUNTIME/venv" && uv pip install --python "$PY" -r server/requirements.txt
  else
    BASE=""
    for c in python3.13 python3.12 python3.11 python3.10; do command -v $c >/dev/null 2>&1 && { BASE=$c; break; }; done
    if [ -z "$BASE" ]; then
      echo "要 Python 3.10 或以上：brew install python@3.12（或者喺 python.org 装），装好再开。"
      exit 1
    fi
    "$BASE" -m venv "$RUNTIME/venv" && "$PY" -m pip install -q -r server/requirements.txt
  fi || { echo "装唔到 Python 套件，睇下网络再试。"; rm -rf "$RUNTIME/venv"; exit 1; }
fi
if [ "$TESTONLY" = 1 ]; then cd server && exec "$PY" -m unittest discover -s tests; fi
# 组员 B 嘅豆包配置（语音 Key、方舟 Key、模型、音色）：本机另放嘅优先，冇就用私有仓库入面嗰份（server/private/）
if [ -z "$DOUBAO_CONFIG" ]; then
  if [ -f "$RUNTIME/doubao.json" ]; then DOUBAO_CONFIG="$RUNTIME/doubao.json"; else DOUBAO_CONFIG="$REPO/server/private/doubao.json"; fi
fi
export DOUBAO_CONFIG
if [ ! -f "$DOUBAO_CONFIG" ]; then
  echo "搵唔到豆包配置：$DOUBAO_CONFIG"
  exit 1
fi
if [ "$VOICE" = sovits ] && [ ! -d "$RUNTIME/gptsovits/GPT_SoVITS/pretrained_models" ]; then
  echo "--voice=sovits 要 GPT-SoVITS 声音模型：$RUNTIME/gptsovits（见 server/README.md）。"
  exit 1
fi
# Supabase 地址同 publishable key：同 App 用同一份（ios/StreetWalk/Services/BackendConfig.swift）
CFG=ios/StreetWalk/Services/BackendConfig.swift
SUPABASE_URL=$(sed -n 's/.*URL(string: "\(https[^"]*\)").*/\1/p' "$CFG")
SUPABASE_ANON_KEY=$(sed -n 's/.*publishableKey = "\([^"]*\)".*/\1/p' "$CFG")
export SUPABASE_URL SUPABASE_ANON_KEY
export ASSISTANT_MODE="${ASSISTANT_MODE:-supabase}"
export ASSISTANT_DATABASE="${ASSISTANT_DATABASE:-$RUNTIME/data/assistant.sqlite3}"
export SPEECH_CACHE_DIR="${SPEECH_CACHE_DIR:-$RUNTIME/data/tts-cache}"
export TTS_PROVIDER="$VOICE"
if [ "$VOICE" = sovits ]; then
  export SOVITS_ROOT="$RUNTIME/gptsovits"
  export SOVITS_REF_WAV="$RUNTIME/ref/cv_yue_f2.wav"
  export SOVITS_REF_TEXT="$RUNTIME/ref/cv_yue_f2.txt"
  # 句子入面有英文（例如英文网名）时，GPT-SoVITS 要用 nltk 嘅英文字典
  export NLTK_DATA="$RUNTIME/nltk_data"
fi
# 理解：有豆包配置就用 B 嘅豆包模型（方舟）；另外设 QWEN_API_KEY 等就改用千问。
mkdir -p "$RUNTIME/data"

IP=$(ipconfig getifaddr en0 2>/dev/null || ipconfig getifaddr en1 2>/dev/null || echo 127.0.0.1)
NAME="街坊行語音 $(scutil --get LocalHostName 2>/dev/null || hostname -s)"
PIDS=""
cleanup() { for p in $PIDS; do kill "$p" 2>/dev/null || true; done; }
trap cleanup EXIT INT TERM

# Bonjour 广播：App 喺同一个 Wi-Fi 自动搵到（TXT 记录带埋地址）
dns-sd -R "$NAME" _jiefongvoice._tcp local "$PORT" "url=http://$IP:$PORT" path=/ >/dev/null 2>&1 &
PIDS="$PIDS $!"
# 服务器开住时唔好闲置瞓眠
caffeinate -i -w $$ &
PIDS="$PIDS $!"

if [ "$TUNNEL" = 1 ]; then
  if command -v cloudflared >/dev/null 2>&1; then
    LOG="$RUNTIME/data/tunnel.log"
    cloudflared tunnel --no-autoupdate --url "http://localhost:$PORT" > "$LOG" 2>&1 &
    PIDS="$PIDS $!"
    ( i=0; while [ $i -lt 40 ]; do
        U=$(grep -o 'https://[a-z0-9-]*\.trycloudflare\.com' "$LOG" | head -1)
        if [ -n "$U" ]; then printf '\n  公網地址（填入 App 設定 → 聲音 → 語音伺服器）：%s\n\n' "$U"; break; fi
        i=$((i + 1)); sleep 1
      done ) &
  else
    echo "未裝 cloudflared：brew install cloudflared 之後再用 --tunnel。"
  fi
fi

echo "──────────────────────────────────────────────"
echo "  街坊行語音伺服器"
echo "  局域網地址：http://$IP:$PORT   （同一個 Wi-Fi 嘅 iPhone 會自動搵到）"
echo "  模擬器：http://127.0.0.1:$PORT"
if [ "$VOICE" = sovits ]; then
  echo "  播報：Mac 本機真人聲（載入約 10–30 秒，未好之前 App 用系統聲音）"
else
  echo "  播報：豆包「小何」粵語聲（組員 B 嗰套；識別、理解都係豆包，Mac 只做轉發）"
fi
echo "──────────────────────────────────────────────"
cd "$REPO/server"
"$PY" -m assistant.serve assistant.app:create_app --factory --host 0.0.0.0 --port "$PORT" --no-access-log --log-level warning
