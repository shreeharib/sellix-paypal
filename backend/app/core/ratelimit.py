"""Per-minute request limits, applied before a request reaches any route.

Counts live in this process's memory (fixed one-minute windows), so a limit is per API
process: with N processes the real limit is up to N times higher, and a restart clears the
counts. That is enough to stop a runaway client or password-style guessing; for hard
guarantees across processes, move the counters to Redis behind the same `RateLimiter`.
"""

import time
from collections.abc import MutableMapping
from dataclasses import dataclass

import structlog
from starlette.datastructures import Headers
from starlette.responses import JSONResponse
from starlette.types import ASGIApp, Receive, Scope, Send

from app.core.config import get_settings
from app.modules.accounts import service as accounts

log = structlog.get_logger()

WINDOW_SECONDS = 60
MAX_KEYS = 50_000  # memory bound: beyond this, expired windows are dropped first

# Paths that are never limited (load balancers poll the health check).
EXEMPT_PATHS = frozenset({"/health", "/openapi.json", "/docs", "/redoc"})


@dataclass(frozen=True)
class Rule:
    name: str
    limit: int


class RateLimiter:
    def __init__(self) -> None:
        self._windows: MutableMapping[str, tuple[int, int]] = {}

    def hit(self, key: str, limit: int, *, now: float | None = None) -> int | None:
        """Count a request. None if allowed, else the seconds until the window resets."""
        if limit <= 0:
            return None
        moment = now if now is not None else time.monotonic()
        window = int(moment // WINDOW_SECONDS)
        started, count = self._windows.get(key, (window, 0))
        if started != window:
            started, count = window, 0
        if count >= limit:
            return max(1, int((window + 1) * WINDOW_SECONDS - moment))
        if len(self._windows) >= MAX_KEYS and key not in self._windows:
            self._evict(window)
        self._windows[key] = (started, count + 1)
        return None

    def _evict(self, window: int) -> None:
        for key in [k for k, (started, _) in self._windows.items() if started != window]:
            del self._windows[key]
        if len(self._windows) >= MAX_KEYS:
            self._windows.clear()  # a flood of distinct clients: start over rather than grow


def rule_for(path: str) -> Rule | None:
    settings = get_settings()
    if path in EXEMPT_PATHS:
        return None
    if path.startswith("/v1/auth/"):
        return Rule("auth", settings.rate_limit_auth_per_minute)
    if path.startswith("/webhooks/"):
        return Rule("webhook", settings.rate_limit_webhook_per_minute)
    if path.startswith("/v1/"):
        return Rule("api", settings.rate_limit_api_per_minute)
    return Rule("pages", settings.rate_limit_api_per_minute)


def client_key(scope: Scope, rule: Rule) -> str:
    """A signed-in user counts on their own; everyone else counts by client address."""
    if rule.name == "api":
        scheme, _, token = Headers(scope=scope).get("authorization", "").partition(" ")
        if scheme.lower() == "bearer" and token:
            try:
                return f"user:{accounts.verify_access_token(token).user_id}"
            except accounts.AuthFailed:
                pass
    client = scope.get("client")
    return f"ip:{client[0] if client else 'unknown'}"


class RateLimitMiddleware:
    """Plain ASGI middleware: no per-request task or body buffering."""

    def __init__(self, app: ASGIApp, limiter: RateLimiter | None = None) -> None:
        self.app = app
        self.limiter = limiter or RateLimiter()

    async def __call__(self, scope: Scope, receive: Receive, send: Send) -> None:
        if scope["type"] != "http" or scope["method"] == "OPTIONS":
            await self.app(scope, receive, send)
            return
        rule = rule_for(scope["path"])
        if rule is not None:
            retry_after = self.limiter.hit(f"{rule.name}:{client_key(scope, rule)}", rule.limit)
            if retry_after is not None:
                log.warning("rate_limited", rule=rule.name, path=scope["path"])
                response = JSONResponse(
                    {"detail": "Too many requests. Please slow down."},
                    status_code=429,
                    headers={"Retry-After": str(retry_after)},
                )
                await response(scope, receive, send)
                return
        await self.app(scope, receive, send)
