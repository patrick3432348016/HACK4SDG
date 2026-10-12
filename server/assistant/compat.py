"""成员 A 加（2026-10-12）：令 B 按 Python 3.11+ 写嘅代码喺 3.10 跑得到。

语音服务器同 GPT-SoVITS 共用一个 Python 3.10 环境（voice-runtime/venv），而 B 新版（豆包实时对话、天文台天气）用咗
3.11 先有嘅 asyncio.timeout，亦假设 asyncio 超时就系内置 TimeoutError（3.11 起两者合一）。
要喺任何第三方库（尤其 websockets）载入之前做，所以由 assistant/__init__.py 第一行引入。3.11 或以上乜都唔做。
"""
import sys

if sys.version_info < (3, 11):
    import asyncio
    import asyncio.exceptions
    import builtins

    import async_timeout

    asyncio.TimeoutError = asyncio.exceptions.TimeoutError = builtins.TimeoutError
    asyncio.timeout = async_timeout.timeout
