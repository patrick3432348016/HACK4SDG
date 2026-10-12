"""Check a running loopback WebSocket server without credentials or cloud calls."""
import asyncio
import json
import urllib.request
from websockets.asyncio.client import connect


async def main():
    with urllib.request.urlopen("http://127.0.0.1:8765/windows/session", timeout=3) as response:
        session = json.load(response)
    assert session["application"] == "hack4sdg-windows-voice"
    async with connect("ws://127.0.0.1:8765/windows/realtime", origin="http://127.0.0.1:8765", proxy=None, open_timeout=3) as socket:
        await socket.send(json.dumps({"token": session["token"], "config": {}}))
        result = json.loads(await asyncio.wait_for(socket.recv(), 3))
        assert result["type"] == "error" and result["code"] == "INVALID_CONFIG"
    print("Real loopback WebSocket upgrade and missing-credential rejection passed. No cloud calls.")


if __name__ == "__main__":
    asyncio.run(main())
