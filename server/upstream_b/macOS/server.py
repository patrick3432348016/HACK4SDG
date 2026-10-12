"""Mac host for the unchanged realtime assistant; config remains outside the app."""
import argparse
import asyncio
from contextlib import asynccontextmanager
import json
from pathlib import Path
import socket
import sys
import threading
import webbrowser

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "backend"))

from assistant.doubao import DoubaoConfig
from assistant.windows import create_windows_app
import uvicorn


def run():
    parser = argparse.ArgumentParser()
    parser.add_argument("--config", type=Path, default=ROOT / "Private" / "voice-config.json")
    parser.add_argument("--open-browser", action="store_true")
    parser.add_argument("--watch-stdin", action="store_true")
    args = parser.parse_args()
    try:
        # The ZIP's explicitly requested keys load locally, never via a command line.
        if args.config.stat().st_size > 12000:
            raise ValueError()
        saved = DoubaoConfig.model_validate_json(args.config.read_bytes())
    except (OSError, ValueError):
        print(json.dumps({"error": "Private/voice-config.json missing or invalid"}), flush=True)
        return 2
    app = create_windows_app()
    original_lifespan = app.router.lifespan_context
    listener = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    listener.bind(("127.0.0.1", 0))
    listener.listen(128)
    address = f"http://127.0.0.1:{listener.getsockname()[1]}"
    server = uvicorn.Server(uvicorn.Config(app, host="127.0.0.1", log_level="error",
                            access_log=False, ws_max_size=65536))

    async def announce():
        while not server.started:
            await asyncio.sleep(.05)
        print(json.dumps({"ready": True, "url": address}), flush=True)
        if args.open_browser:
            await asyncio.to_thread(webbrowser.open, address)

    @asynccontextmanager
    async def lifespan(instance):
        async with original_lifespan(instance):
            instance.state.voice_config = saved
            announcement = asyncio.create_task(announce())
            try:
                yield
            finally:
                announcement.cancel()

    app.router.lifespan_context = lifespan

    def monitor_parent():
        # Xcode shell owns stdin: EOF after crash/exit stops this child as well.
        try:
            sys.stdin.buffer.read()
        finally:
            server.should_exit = True

    if args.watch_stdin:
        threading.Thread(target=monitor_parent, daemon=True).start()
    try:
        server.run(sockets=[listener])
    finally:
        listener.close()
    return 0


if __name__ == "__main__":
    sys.exit(run())
