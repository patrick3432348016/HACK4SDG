#!/bin/sh
# 街坊行 · Mac 语音服务器（粤语真人声 + 语音助手）。一条命令开：
#   tools/voice_server.sh             # 局域网：同一个 Wi-Fi 嘅 iPhone 自动搵到（Bonjour _jiefongvoice._tcp）
#   tools/voice_server.sh --tunnel    # 再开 Cloudflare 临时公网地址（https://….trycloudflare.com，唔使账号）
#   tools/voice_server.sh --verbose   # 日志印埋合成嘅句子（排查用）
#   tools/voice_server.sh --test      # 只跑服务器测试
# 声音模型同 Python 环境喺仓库外面：$VOICE_RUNTIME（默认 ~/Desktop/HACK/voice-runtime，见 server/README.md）。
# 部 Mac 要保持开机唔好瞓（脚本会用 caffeinate 防止闲置瞓眠；合埋盖照样会瞓）。Ctrl-C 停。
set -e
cd "$(dirname "$0")/.."
REPO=$(pwd)
RUNTIME=${VOICE_RUNTIME:-$HOME/Desktop/HACK/voice-runtime}
PY="$RUNTIME/venv/bin/python"
PORT=${PORT:-8765}
TUNNEL=0
for a in "$@"; do
  case "$a" in
    --tunnel) TUNNEL=1 ;;
    --verbose) export VOICE_LOG_TEXT=1 ;;
    --test) cd server && exec "$PY" -m unittest discover -s tests ;;
    --port=*) PORT=${a#--port=} ;;
    *) echo "唔识呢个参数：$a"; exit 2 ;;
  esac
done
if [ ! -x "$PY" ] || [ ! -d "$RUNTIME/gptsovits/GPT_SoVITS/pretrained_models" ]; then
  echo "搵唔到语音模型环境：$RUNTIME"
  echo "按 server/README.md「第一次安装」做一次（大约 3 GB）。"
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
export TTS_PROVIDER="${TTS_PROVIDER:-sovits}"
export SOVITS_ROOT="$RUNTIME/gptsovits"
export SOVITS_REF_WAV="$RUNTIME/ref/cv_yue_f2.wav"
export SOVITS_REF_TEXT="$RUNTIME/ref/cv_yue_f2.txt"
# 句子入面有英文（例如英文网名）时，GPT-SoVITS 要用 nltk 嘅英文字典
export NLTK_DATA="$RUNTIME/nltk_data"
# 以后有通义千问 key：export QWEN_API_KEY=… QWEN_BASE_URL=… QWEN_MODEL=… 再开，就会用模型理解（冇就用规则）。
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
echo "  聲音模型載入中（約 10–30 秒），之後先有真人聲；未好之前 App 用系統聲音。"
echo "──────────────────────────────────────────────"
cd "$REPO/server"
"$PY" -m uvicorn assistant.app:create_app --factory --host 0.0.0.0 --port "$PORT" --no-access-log --log-level warning
