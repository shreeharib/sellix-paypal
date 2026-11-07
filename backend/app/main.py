"""API process: Meta and PayPal webhooks, OAuth and payment pages, and the REST API."""

import asyncio
from collections.abc import AsyncIterator
from contextlib import asynccontextmanager, suppress
from pathlib import Path

import structlog
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import HTMLResponse

from app.api.v1 import router as v1_router
from app.core.config import get_settings
from app.core.db import dispose_engine
from app.core.jobs import jobs, run_worker
from app.core.logging import configure_logging
from app.modules.agent import service as agent
from app.modules.channels.router import router as channels_router
from app.modules.payments.router import router as payments_router
from app.webhooks import meta, paypal

log = structlog.get_logger()

SIMULATOR_PAGE = Path(__file__).parent / "simulator.html"


@asynccontextmanager
async def lifespan(_: FastAPI) -> AsyncIterator[None]:
    settings = get_settings()
    missing = settings.missing_required()
    if missing:
        if settings.app_env != "local":
            raise RuntimeError(f"Missing required settings: {', '.join(missing)}")
        log.warning("config.missing_settings", settings=missing)
    agent.load_prompts()

    async with jobs.open_async():
        worker: asyncio.Task[None] | None = None
        if settings.run_worker_in_process:
            worker = asyncio.create_task(run_worker(install_signal_handlers=False))
            worker.add_done_callback(_log_worker_exit)
        try:
            yield
        finally:
            if worker is not None:
                worker.cancel()
                with suppress(asyncio.CancelledError):
                    await worker
            await dispose_engine()


def _log_worker_exit(task: asyncio.Task[None]) -> None:
    if not task.cancelled() and task.exception() is not None:
        log.error("worker.crashed", error=repr(task.exception()))


def create_app() -> FastAPI:
    settings = get_settings()
    configure_logging(settings.log_level, json_logs=settings.app_env != "local")

    app = FastAPI(title="sellix API", version="0.1.0", lifespan=lifespan)
    app.add_middleware(
        CORSMiddleware,
        allow_origins=[o.strip() for o in settings.web_app_origins.split(",") if o.strip()],
        allow_methods=["GET", "POST", "PUT", "PATCH", "DELETE"],
        allow_headers=["Authorization", "Content-Type"],
    )
    app.include_router(meta.router)
    app.include_router(paypal.router)
    app.include_router(channels_router)
    app.include_router(payments_router)
    app.include_router(v1_router)

    @app.get("/simulator", include_in_schema=False)
    async def simulator() -> HTMLResponse:
        """The simulator page (it calls /v1/simulator with the merchant's own token)."""
        return HTMLResponse(SIMULATOR_PAGE.read_text(encoding="utf-8"))

    @app.get("/health", tags=["ops"])
    async def health() -> dict[str, str]:
        return {"status": "ok", "env": settings.app_env}

    return app


app = create_app()
