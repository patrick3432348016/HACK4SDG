#!/bin/bash
set -euo pipefail
cd -- "$(dirname -- "$0")/.."
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"
if ! command -v python3.12 >/dev/null 2>&1; then
  echo "请先安装 Python 3.12（python.org macOS 安装包，或 brew install python@3.12），然后再次运行。"
  read -r -p "按回车关闭。" _
  exit 1
fi
if [[ ! -x .venv/bin/python ]]; then
  python3.12 -m venv .venv
fi
if ! .venv/bin/python -c 'import sys; assert sys.version_info[:2] == (3, 12)' ; then
  echo "项目 .venv 不是 Python 3.12，请将它改名备份后重试。"
  exit 1
fi
.venv/bin/python -m pip install -r backend/requirements.txt -c backend/constraints.txt
chmod 600 Private/voice-config.json
echo "依赖安装完成。现在可打开 macOS/VoiceAssistantMac.xcodeproj，选择 My Mac 并运行。"
echo "不使用 Xcode 时，也可双击 macOS/Run-in-Browser.command。"
read -r -p "按回车关闭。" _
