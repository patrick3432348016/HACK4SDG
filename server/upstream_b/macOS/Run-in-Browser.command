#!/bin/bash
set -euo pipefail
cd -- "$(dirname -- "$0")/.."
if [[ ! -x .venv/bin/python ]]; then
  echo "请先运行 macOS/Setup.command。"
  read -r -p "按回车关闭。" _
  exit 1
fi
exec .venv/bin/python macOS/server.py --open-browser
