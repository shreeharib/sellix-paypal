# One image for both processes: the API (default command) and the job worker
# (override the command with `python -m app.worker`).
FROM python:3.12-slim

ENV PYTHONUNBUFFERED=1 PYTHONDONTWRITEBYTECODE=1 UV_LINK_MODE=copy
RUN pip install --no-cache-dir uv
WORKDIR /app

# Dependencies first, so code changes don't reinstall them.
COPY pyproject.toml uv.lock ./
RUN uv sync --locked --no-dev --no-install-project

COPY app ./app
RUN uv sync --locked --no-dev

RUN useradd --create-home --uid 10001 sellix
USER sellix
ENV PATH="/app/.venv/bin:$PATH"

# API_WORKERS: API processes per container. Each has its own database pool (DB_POOL_SIZE).
# FORWARDED_ALLOW_IPS: the proxy addresses whose X-Forwarded-For is trusted (rate limits use it).
ENV API_WORKERS=2 PORT=8000 FORWARDED_ALLOW_IPS=127.0.0.1
EXPOSE 8000
CMD ["sh", "-c", "exec uvicorn app.main:app --host 0.0.0.0 --port $PORT --workers $API_WORKERS --proxy-headers --timeout-graceful-shutdown 20"]
