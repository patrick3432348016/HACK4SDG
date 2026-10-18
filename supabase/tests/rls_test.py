"""Live anonymous-account RLS/function checks: python3 -I rls_test.py <url> <publishable_key>; require authorized test data and cleanup."""
import json, sys, uuid, urllib.request, urllib.error

URL, KEY = sys.argv[1], sys.argv[2]


def call(method, path, token=None, body=None, prefer=None):
    req = urllib.request.Request(URL + path, method=method,
                                 data=None if body is None else json.dumps(body).encode())
    req.add_header("apikey", KEY)
    req.add_header("Content-Type", "application/json")
    if token:
        req.add_header("Authorization", "Bearer " + token)
    if prefer:
        req.add_header("Prefer", prefer)
    try:
        with urllib.request.urlopen(req) as r:
            raw = r.read().decode()
            return r.status, (json.loads(raw) if raw else None)
    except urllib.error.HTTPError as e:
        raw = e.read().decode()
        try:
            return e.code, json.loads(raw)
        except Exception:
            return e.code, raw


def signup():
    s, r = call("POST", "/auth/v1/signup", body={})
    assert s == 200, r
    return r["access_token"], r["user"]["id"]


results = []


def check(name, ok, detail=""):
    results.append(ok)
    print(("PASS " if ok else "FAIL ") + name + ("" if ok else f"  -> {detail}"))


ta, a = signup()
tb, b = signup()
tc, c = signup()  # Third user lives far away.
for t, uid, nick, tx in [(ta, a, "測試甲", 0), (tb, b, "測試乙", 1), (tc, c, "測試丙", 50)]:
    s, r = call("POST", "/rest/v1/profiles", t, {"id": uid, "nickname": nick, "tile_x": tx, "tile_y": 0,
                                                  "block": "4座", "floor": 12, "streak": 3,
                                                  "streak_day": "2099-01-01"}, "return=minimal")
    check(f"{nick} 建立自己资料", s in (200, 201), r)

s, r = call("POST", "/rest/v1/profiles", ta, {"id": b, "nickname": "冒充", "tile_x": 0, "tile_y": 0})
check("不能替别人建资料", s >= 400, r)

s, r = call("GET", "/rest/v1/profiles?select=*", ta)
check("profiles 只看到自己", s == 200 and len(r) == 1 and r[0]["id"] == a, r)

s, r = call("POST", "/rest/v1/rpc/community_board", ta, {})
ids = {x["id"] for x in r} if s == 200 else set()
check("排行榜有附近的甲乙、没有远处的丙", s == 200 and a in ids and b in ids and c not in ids, r)
row_b = next((x for x in r if x["id"] == b), {}) if s == 200 else {}
check("排行榜不含座数楼层字段", "floor" not in row_b and "block" not in row_b, row_b)

s, r = call("POST", "/rest/v1/neighbors", ta, {"owner": a, "other": b})
check("不能直接插入街坊关系", s >= 400, r)

s, r = call("PUT" if False else "POST", "/rest/v1/outings", tb, {"user_id": b, "landmark_name": "涼亭"}, "return=minimal")
check("乙发出门状态", s in (200, 201), r)
s, r = call("GET", "/rest/v1/outings?select=*", ta)
check("未成为街坊时甲看不到乙出门", s == 200 and r == [], r)

s, r = call("POST", "/rest/v1/signals", ta, {"from_user": a, "to_user": b, "kind": "poke"})
check("非街坊不能发信号", s >= 400, r)

code = uuid.uuid4().hex
s, r = call("POST", "/rest/v1/rpc/link_neighbor", ta, {"p_code": code})
check("甲先提交码：暂时配不上", s == 200 and r == [], r)
s, r = call("POST", "/rest/v1/rpc/link_neighbor", tb, {"p_code": code})
check("乙提交同一个码：配上，返回甲的资料", s == 200 and len(r) == 1 and r[0]["id"] == a, r)
s, r = call("POST", "/rest/v1/rpc/link_neighbor", tc, {"p_code": code})
check("码只用一次：丙拿同一个码配不上", s == 200 and r == [], r)
s, r = call("POST", "/rest/v1/rpc/link_neighbor", ta, {"p_code": code})
check("二维码出示方（甲）再问同一个码：知道乙扫咗", s == 200 and len(r) == 1 and r[0]["id"] == b, r)
s, r = call("POST", "/rest/v1/rpc/link_neighbor", tc, {"p_code": code})
check("丙之后再试仍然配不上", s == 200 and r == [], r)

s, r = call("GET", "/rest/v1/outings?select=*", ta)
check("成为街坊后甲看到乙出门", s == 200 and len(r) == 1 and r[0]["landmark_name"] == "涼亭", r)
s, r = call("GET", "/rest/v1/outings?select=*", tc)
check("丙看不到乙出门", s == 200 and r == [], r)

s, r = call("POST", "/rest/v1/rpc/my_neighbors", ta, {})
check("甲的街坊名单有乙、带楼层和出门地标",
      s == 200 and len(r) == 1 and r[0]["id"] == b and r[0]["floor"] == 12 and r[0]["out_at"] == "涼亭", r)

s, r = call("PATCH", f"/rest/v1/neighbors?owner=eq.{b}&other=eq.{a}", tb, {"send_remind": False}, "return=minimal")
check("乙关掉对甲的「发送」", s in (200, 204), r)
s, r = call("GET", "/rest/v1/outings?select=*", ta)
check("乙关了发送后甲看不到", s == 200 and r == [], r)
call("PATCH", f"/rest/v1/neighbors?owner=eq.{b}&other=eq.{a}", tb, {"send_remind": True}, "return=minimal")

s, r = call("POST", "/rest/v1/signals", ta, {"from_user": a, "to_user": b, "kind": "poke"}, "return=minimal")
check("街坊之间可以拍一拍", s in (200, 201), r)
s, r = call("GET", "/rest/v1/signals?select=*", tb)
check("乙收到信号", s == 200 and len(r) == 1, r)
s, r = call("GET", "/rest/v1/signals?select=*", tc)
check("丙看不到别人的信号", s == 200 and r == [], r)

mid = str(uuid.uuid4())
s, r = call("POST", "/rest/v1/meetups", ta, {"id": mid, "inviter": a, "invitee": b, "at": "2099-01-01T10:00:00Z",
                                            "landmark_name": "涼亭"}, "return=minimal")
check("甲约乙", s in (200, 201), r)
s, r = call("POST", "/rest/v1/meetups", tc, {"inviter": c, "invitee": a, "at": "2099-01-01T10:00:00Z"})
check("丙不能约非街坊", s >= 400, r)
s, r = call("PATCH", f"/rest/v1/meetups?id=eq.{mid}", tb, {"status": "accepted", "updated_by": b}, "return=representation")
check("乙接受", s == 200 and len(r) == 1 and r[0]["status"] == "accepted", r)
s, r = call("PATCH", f"/rest/v1/meetups?id=eq.{mid}", tb, {"invitee": c}, "return=representation")
check("不能改约会双方是谁", s >= 400, r)

s, r = call("DELETE", f"/rest/v1/neighbors?owner=eq.{a}&other=eq.{b}", ta)
check("甲解除街坊", s in (200, 204), r)
s, r = call("POST", "/rest/v1/rpc/my_neighbors", tb, {})
check("解除后乙的名单也没有甲（只要一方删就不再互为街坊）", s == 200 and r == [], r)
s, r = call("GET", "/rest/v1/outings?select=*", ta)
check("解除后甲看不到乙出门", s == 200 and r == [], r)

s, r = call("POST", "/rest/v1/reports", ta, {"user_id": a, "tile_x": 0, "tile_y": 0, "landmark_name": "涼亭",
                                            "kind": "sunny", "raw_text": "呢度好曬"}, "return=minimal")
check("甲提交反映", s in (200, 201), r)
s, r = call("GET", "/rest/v1/reports?select=*", tb)
check("乙看不到甲的反映原话", s == 200 and r == [], r)
s, r = call("POST", "/rest/v1/rpc/monthly_report", tb, {})
check("月报不足 10 人不出", s == 200 and r == [], r)

s, r = call("POST", "/rest/v1/rpc/community_board", None, {})
check("未登录不能看排行榜", s >= 400, r)

print(f"\n{sum(results)}/{len(results)} passed")
print("TEST_USERS", a, b, c)
