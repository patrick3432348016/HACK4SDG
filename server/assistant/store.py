"""SQLite state, bounded lifetimes, ownership and atomic confirmation claims."""
from contextlib import contextmanager
from datetime import datetime, timezone
import json
from pathlib import Path
import sqlite3
import time
from uuid import uuid4
from .errors import AssistantError


class Store:
    def __init__(self, path: str):
        Path(path).parent.mkdir(parents=True, exist_ok=True)
        self.path = path
        with self.connection() as db:
            db.executescript("""
                PRAGMA journal_mode=WAL;
                CREATE TABLE IF NOT EXISTS sessions (
                    id TEXT PRIMARY KEY, owner TEXT NOT NULL, revision INTEGER NOT NULL,
                    payload TEXT NOT NULL, updated REAL NOT NULL);
                CREATE TABLE IF NOT EXISTS drafts (
                    id TEXT PRIMARY KEY, owner TEXT NOT NULL, session_id TEXT NOT NULL,
                    revision INTEGER NOT NULL, payload TEXT NOT NULL, expires REAL NOT NULL,
                    status TEXT NOT NULL, receipt TEXT, updated REAL NOT NULL);
                CREATE TABLE IF NOT EXISTS demo_receipts (
                    id TEXT PRIMARY KEY, owner TEXT NOT NULL, payload TEXT NOT NULL);
                CREATE INDEX IF NOT EXISTS draft_session ON drafts(session_id);
                CREATE INDEX IF NOT EXISTS session_owner ON sessions(owner);
            """)

    @contextmanager
    def connection(self):
        db = sqlite3.connect(self.path, timeout=5)
        db.row_factory = sqlite3.Row
        try:
            yield db
            db.commit()
        except Exception:
            db.rollback()
            raise
        finally:
            db.close()

    def session(self, session_id, owner):
        if session_id is None:
            return {"id": uuid4().hex, "revision": 0, "payload": {}}
        with self.connection() as db:
            row = db.execute("SELECT * FROM sessions WHERE id=? AND owner=?", (session_id, owner)).fetchone()
        if row is None or row["updated"] < time.time() - 86400:
            raise AssistantError("SESSION_NOT_FOUND", "会话不存在或已过期，请开始新对话。", 404)
        return {**dict(row), "payload": json.loads(row["payload"])}

    def save(self, session, owner, payload, draft_payload=None, ttl=600):
        now, revision = time.time(), session["revision"] + 1
        draft_id = uuid4().hex if draft_payload else None
        if draft_id:
            payload = {**payload, "draft_id": draft_id}
        with self.connection() as db:
            db.execute("BEGIN IMMEDIATE")
            pending = db.execute("SELECT 1 FROM drafts WHERE session_id=? AND status IN ('executing','uncertain')", (session["id"],)).fetchone()
            if pending:
                raise AssistantError("ACTION_UNRESOLVED", "上次操作结果尚未确认，请先查询原操作结果。", 409)
            if session["revision"] == 0:
                db.execute("INSERT INTO sessions VALUES (?,?,?,?,?)", (session["id"], owner, revision, json.dumps(payload), now))
            else:
                cursor = db.execute("UPDATE sessions SET revision=?,payload=?,updated=? WHERE id=? AND owner=? AND revision=?",
                                    (revision, json.dumps(payload), now, session["id"], owner, session["revision"]))
                if cursor.rowcount != 1:
                    raise AssistantError("CONVERSATION_CHANGED", "会话已更新，请重新查看最新结果。", 409)
            db.execute("UPDATE drafts SET status='cancelled',updated=? WHERE session_id=? AND status='pending'", (now, session["id"]))
            if draft_id:
                db.execute("INSERT INTO drafts VALUES (?,?,?,?,?,?,?,?,?)",
                           (draft_id, owner, session["id"], revision, json.dumps(draft_payload), now + ttl, "pending", None, now))
        return draft_id

    def draft(self, draft_id, owner):
        with self.connection() as db:
            row = db.execute("SELECT * FROM drafts WHERE id=? AND owner=?", (draft_id, owner)).fetchone()
        if row is None:
            raise AssistantError("DRAFT_NOT_FOUND", "操作不存在。", 404)
        return {**dict(row), "payload": json.loads(row["payload"]), "receipt": json.loads(row["receipt"]) if row["receipt"] else None}

    def claim(self, draft_id, owner):
        with self.connection() as db:
            db.execute("BEGIN IMMEDIATE")
            row = db.execute("SELECT * FROM drafts WHERE id=? AND owner=?", (draft_id, owner)).fetchone()
            if row is None:
                raise AssistantError("DRAFT_NOT_FOUND", "操作不存在。", 404)
            if row["status"] != "pending":
                return False
            if row["expires"] < time.time():
                raise AssistantError("DRAFT_EXPIRED", "确认卡已过期，请重新提出请求。", 409)
            session = db.execute("SELECT revision FROM sessions WHERE id=?", (row["session_id"],)).fetchone()
            if session is None or session["revision"] != row["revision"]:
                raise AssistantError("STALE_DRAFT", "这张确认卡已被新请求替代。", 409)
            db.execute("UPDATE drafts SET status='executing',updated=? WHERE id=?", (time.time(), draft_id))
        return True

    def finish(self, draft_id, status, receipt=None):
        with self.connection() as db:
            db.execute("UPDATE drafts SET status=?,receipt=?,updated=? WHERE id=? AND status IN ('executing','uncertain')",
                       (status, json.dumps(receipt) if receipt else None, time.time(), draft_id))

    def cancel(self, draft_id, owner):
        with self.connection() as db:
            db.execute("BEGIN IMMEDIATE")
            row = db.execute("SELECT status FROM drafts WHERE id=? AND owner=?", (draft_id, owner)).fetchone()
            if row is None:
                raise AssistantError("DRAFT_NOT_FOUND", "操作不存在。", 404)
            if row["status"] not in {"pending", "cancelled"}:
                raise AssistantError("CANNOT_CANCEL", "操作已提交，不能把本地取消当成撤回。请先查询结果。", 409)
            db.execute("UPDATE drafts SET status='cancelled',updated=? WHERE id=?", (time.time(), draft_id))

    def demo_execute(self, draft_id, owner, payload):
        receipt = {"status": "succeeded", "receipt_id": "demo-" + draft_id, "message": "测试记录已保存；未发送真实邀请或修改真实账号。"}
        with self.connection() as db:
            db.execute("INSERT OR IGNORE INTO demo_receipts VALUES (?,?,?)", (draft_id, owner, json.dumps(receipt)))
            return json.loads(db.execute("SELECT payload FROM demo_receipts WHERE id=? AND owner=?", (draft_id, owner)).fetchone()[0])

    def demo_receipt(self, draft_id, owner):
        with self.connection() as db:
            row = db.execute("SELECT payload FROM demo_receipts WHERE id=? AND owner=?", (draft_id, owner)).fetchone()
        return json.loads(row[0]) if row else {"status": "not_found"}

    def cleanup(self):
        """24h conversations, 30d operation receipts; unresolved actions retained for reconciliation."""
        now = time.time()
        with self.connection() as db:
            db.execute("DELETE FROM sessions WHERE updated<? AND id NOT IN (SELECT session_id FROM drafts WHERE status IN ('executing','uncertain'))", (now - 86400,))
            db.execute("DELETE FROM drafts WHERE updated<? AND status NOT IN ('executing','uncertain')", (now - 30 * 86400,))
            db.execute("DELETE FROM demo_receipts WHERE id NOT IN (SELECT id FROM drafts)")
