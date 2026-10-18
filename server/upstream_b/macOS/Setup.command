#!/bin/bash
set -euo pipefail
cd -- "$(dirname -- "$0")/.."
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"
if ! command -v python3.12 >/dev/null 2>&1; then
  echo "Install Python 3.12 using the python.org macOS installer or brew install python@3.12, then retry."
  read -r -p "Press Enter to close." _
  exit 1
fi
if [[ ! -x .venv/bin/python ]]; then
  python3.12 -m venv .venv
fi
if ! .venv/bin/python -c 'import sys; assert sys.version_info[:2] == (3, 12)' ; then
  echo "The project .venv does not use Python 3.12. Rename it as a backup, then retry."
  exit 1
fi
.venv/bin/python -m pip install -r backend/requirements.txt -c backend/constraints.txt
chmod 600 Private/voice-config.json
echo "Dependencies installed. Open macOS/VoiceAssistantMac.xcodeproj, select My Mac, and run."
echo "Without Xcode, double-click macOS/Run-in-Browser.command instead."
read -r -p "Press Enter to close." _
