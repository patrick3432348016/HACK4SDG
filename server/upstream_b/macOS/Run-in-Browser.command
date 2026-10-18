#!/bin/bash
set -euo pipefail
cd -- "$(dirname -- "$0")/.."
if [[ ! -x .venv/bin/python ]]; then
  echo "Run macOS/Setup.command first."
  read -r -p "Press Enter to close." _
  exit 1
fi
exec .venv/bin/python macOS/server.py --open-browser
