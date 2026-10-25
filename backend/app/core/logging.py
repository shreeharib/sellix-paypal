"""Structured logging: readable lines locally, JSON everywhere else.

Libraries that use the standard logging module (the job queue, SQLAlchemy, uvicorn) are
routed through the same renderer, so every log line has the same shape.
"""

import logging
import sys

import structlog

_SHARED_PROCESSORS: list[structlog.types.Processor] = [
    structlog.contextvars.merge_contextvars,
    structlog.stdlib.add_log_level,
    structlog.stdlib.add_logger_name,
    structlog.processors.TimeStamper(fmt="iso", utc=True),
]


def configure_logging(level: str = "INFO", *, json_logs: bool = False) -> None:
    renderer: structlog.types.Processor = (
        structlog.processors.JSONRenderer() if json_logs else structlog.dev.ConsoleRenderer()
    )
    numeric_level = logging.getLevelNamesMapping()[level.upper()]

    structlog.configure(
        processors=[
            *_SHARED_PROCESSORS,
            structlog.stdlib.ProcessorFormatter.wrap_for_formatter,
        ],
        logger_factory=structlog.stdlib.LoggerFactory(),
        wrapper_class=structlog.make_filtering_bound_logger(numeric_level),
        cache_logger_on_first_use=True,
    )

    handler = logging.StreamHandler(sys.stdout)
    handler.setFormatter(
        structlog.stdlib.ProcessorFormatter(
            foreign_pre_chain=_SHARED_PROCESSORS,
            processors=[structlog.stdlib.ProcessorFormatter.remove_processors_meta, renderer],
        )
    )
    root = logging.getLogger()
    root.handlers = [handler]
    root.setLevel(numeric_level)
    # HTTP clients log full request URLs, and Instagram's token endpoints carry the app
    # secret and access tokens in the query string.
    for name in ("httpx2", "httpx", "httpcore"):
        logging.getLogger(name).setLevel(max(numeric_level, logging.WARNING))
