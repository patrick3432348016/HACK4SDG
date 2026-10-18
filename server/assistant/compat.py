"""A, 2026-10-12: compatibility for B's Python 3.11+ code on Python 3.10.

The voice server shares a Python 3.10 environment with GPT-SoVITS, while B's new code uses
asyncio.timeout and the unified built-in TimeoutError introduced in Python 3.11.
Load before third-party libraries, especially websockets, through assistant/__init__.py; no-op on 3.11+.
"""
import sys

if sys.version_info < (3, 11):
    import asyncio
    import asyncio.exceptions
    import builtins

    import async_timeout

    asyncio.TimeoutError = asyncio.exceptions.TimeoutError = builtins.TimeoutError
    asyncio.timeout = async_timeout.timeout
