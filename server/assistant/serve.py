"""A, 2026-10-12: python -m assistant.serve accepts uvicorn arguments.

Load assistant.compat before uvicorn and websockets for Python 3.10,
ensuring a consistent TimeoutError; voice_server.sh uses this entry point.
"""
import uvicorn

if __name__ == "__main__":
    uvicorn.main()
