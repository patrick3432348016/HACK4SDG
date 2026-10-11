"""One command: tests + project structure + a temporary real HTTP demo server.

Uses a temporary database, loopback binding and blank vendor settings. Never sends
real business requests or starts a public service. Always stops its own child.
"""
import os
from pathlib import Path
import socket
import subprocess
import sys
import tempfile
import time
import urllib.error
import urllib.request

root = Path(__file__).resolve().parents[1]
subprocess.run([sys.executable, "-m", "unittest", "discover", "-s", "tests", "-v"], cwd=root, check=True)
# 成员 A：check_delivery.py（检查 B 独立交付包嘅 Xcode 工程）喺呢个仓库唔适用，已删。

with tempfile.TemporaryDirectory(prefix="assistant-verify-") as temporary:
    with socket.socket() as reservation:
        reservation.bind(("127.0.0.1", 0))
        port = reservation.getsockname()[1]
    env = os.environ.copy()
    env.update({"ASSISTANT_MODE": "demo", "ASSISTANT_DATABASE": str(Path(temporary) / "test.sqlite3"),
                "DEMO_TOKEN": "local-demo-only"})
    env["TTS_PROVIDER"] = "none"
    for name in ("SUPABASE_URL", "SUPABASE_ANON_KEY", "AZURE_SPEECH_KEY", "AZURE_STT_URL", "AZURE_TTS_URL", "QWEN_API_KEY",
                 "QWEN_BASE_URL", "QWEN_MODEL", "BUSINESS_BASE_URL"):
        env[name] = ""
    flags = subprocess.CREATE_NO_WINDOW if os.name == "nt" else 0
    server = subprocess.Popen([sys.executable, "-m", "uvicorn", "assistant.app:create_app", "--factory",
        "--host", "127.0.0.1", "--port", str(port), "--no-access-log"],
        cwd=root, env=env, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE, creationflags=flags)
    try:
        deadline = time.monotonic() + 15
        while True:
            if server.poll() is not None:
                raise RuntimeError("Temporary server exited before verification: " + server.stderr.read().decode(errors="replace"))
            try:
                with urllib.request.urlopen(f"http://127.0.0.1:{port}/healthz", timeout=1) as response:
                    if response.status == 200:
                        break
            except (OSError, urllib.error.URLError):
                pass
            if time.monotonic() > deadline:
                raise TimeoutError("Temporary server did not become ready within 15 seconds")
            time.sleep(.1)
        subprocess.run([sys.executable, str(root / "tools/smoke.py"), "--url", f"http://127.0.0.1:{port}"], check=True)
    finally:
        if server.poll() is None:
            server.terminate()
            try:
                server.wait(timeout=5)
            except subprocess.TimeoutExpired:
                server.kill()
                server.wait(timeout=5)
        server.stderr.close()
print("Backend verification complete. iOS compilation, device tests and real providers remain separate gates.")
