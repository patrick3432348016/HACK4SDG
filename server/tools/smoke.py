"""Exercise a running DEMO server through real HTTP. Does not call vendor APIs."""
import argparse
import json
import urllib.error
import urllib.request

parser = argparse.ArgumentParser()
parser.add_argument("--url", default="http://127.0.0.1:8000")
parser.add_argument("--token", default="local-demo-only")
args = parser.parse_args()


def request(path, body=None):
    req = urllib.request.Request(args.url.rstrip("/") + path,
        data=json.dumps(body).encode() if body is not None else None,
        headers={"Authorization": "Bearer " + args.token, "Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=10) as response:
        return json.load(response)


capabilities = request("/v1/capabilities")
assert capabilities["mode"] == "demo", "Smoke script is only allowed to write demo records"
reply = request("/v1/assistant/turn", {"text": "约陈伯明天下午四点散步，遮荫优先，最多15分钟", "locale": "zh-HK"})
assert reply["status"] == "choose_place", reply
reply = request(f"/v1/conversations/{reply['conversation_id']}/choice", {"kind": "place", "value": reply["choices"][0]["id"]})
assert reply["status"] == "needs_confirmation", reply
first = request(f"/v1/drafts/{reply['draft_id']}/confirm", {})
second = request(f"/v1/drafts/{reply['draft_id']}/confirm", {})
assert first["status"] == "completed" and first["demo"]
assert first["data"]["receipt_id"] == second["data"]["receipt_id"]
print("HTTP smoke passed: interpret -> choose -> confirm -> duplicate confirm preserves receipt. Demo data only.")
