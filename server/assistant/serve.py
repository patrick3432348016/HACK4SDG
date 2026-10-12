"""成员 A 加（2026-10-12）：`python -m assistant.serve …`（参数同 uvicorn）。

经 assistant 包先载入 compat（Python 3.10 兼容，见 compat.py），之后先载入 uvicorn 同 websockets，
等佢哋同 B 嘅代码用同一个 TimeoutError。tools/voice_server.sh 用呢个开服务器。
"""
import uvicorn

if __name__ == "__main__":
    uvicorn.main()
