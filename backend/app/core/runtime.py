"""Event loop setup.

psycopg's async mode needs a selector event loop, which Windows doesn't use by default.
Linux (production) is unaffected. Used by the dev server (`--loop`), the worker, the CLI
and the tests.
"""

import asyncio
import sys


def new_event_loop() -> asyncio.AbstractEventLoop:
    if sys.platform == "win32":
        return asyncio.SelectorEventLoop()
    return asyncio.new_event_loop()
