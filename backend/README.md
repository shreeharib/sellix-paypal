# sellix backend

Python 3.12 · FastAPI · SQLAlchemy 2 (async) on psycopg 3 · Postgres · procrastinate (job queue in Postgres) · uv. One codebase, run as the API process with the job worker inside it (or as a separate worker). Module map and rules: [docs/dev-plan.md](../docs/dev-plan.md), section 5.

## First-time setup

```bash
uv sync                                   # dependencies into .venv
cp .env.example .env
uv run python -m app.cli generate-secrets # paste the output into .env
```

Fill in the rest of `.env` from the team password manager (Meta app, LLM).

**Database**, either:
- the Supabase CLI: `supabase start`, then `supabase db reset` (applies `supabase/migrations`), or
- plain Docker, from the repo root: `just db-up` then `just db-reset`.

Both give `postgresql://postgres:postgres@localhost:54322/...`; the default `DATABASE_URL` uses the database `sellix`.

## Run it

```bash
just dev        # or: uv run uvicorn app.main:app --reload --reload-include .env --loop app.core.runtime:new_event_loop
```

- Health check: http://localhost:8000/health · API docs: http://localhost:8000/docs
- The `--loop` option matters on Windows only: psycopg's async mode needs a selector event loop.
- Meta and PayPal need a public HTTPS address. Locally, run a tunnel and set `PUBLIC_BASE_URL` to it:
  `docker run -d --name sellix-tunnel cloudflare/cloudflared:latest tunnel --no-autoupdate --url http://host.docker.internal:8000`
  (the URL is in `docker logs sellix-tunnel`; it changes every time the tunnel restarts).

## Set up a merchant (until the app's onboarding exists)

```bash
just cli create-merchant --name "Sweet Crumbs"
just cli set-shop-profile --merchant-id <id> --file shop.md
just cli set-stock --merchant-id <id> --file stock.json        # see `just cli set-stock --help`
just cli connect-instagram --merchant-id <id>                 # prints the link to open
```

Other commands: `set-agent on|off`, `resume-conversation`, `generate-secrets`. See `just cli --help`.

## Check it (the same checks CI runs)

```bash
uv run ruff check .          # lint
uv run ruff format --check . # formatting (`uv run ruff format .` fixes it)
uv run basedpyright          # types
uv run pytest                # tests; database tests need Postgres on :54322 (skipped if absent)
```

## How a customer message flows

1. `webhooks/meta.py`: verify the signature → store the raw event once (`webhook_events`) → queue a job → answer 200.
2. `webhooks/tasks.py`: parse it (`channels`) → store customer and message (`conversations`) → queue one agent turn per chat, a few seconds later, so a burst of messages gets one reply.
3. `conversations.run_turn`: build the history → `agent` (shop profile + today's stock → model → validated JSON) → open an escalation if the owner is needed → send through `channels` → record the result.
4. Orders: the agent asks the system for a **quote** (exact prices and totals come from code, never the model), then, once the customer agrees, to **place** the order. That holds the stock in one conditional update and creates a PayPal sandbox order. The link goes into the reply.
5. The order is paid only when PayPal confirms the capture (return page or verified webhook). Held stock becomes sold, and a system note makes the agent thank the customer in their language. Unpaid holds expire after `PAYMENT_HOLD_MINUTES` and the stock goes back on sale.
6. Echoes of the merchant typing in the Instagram app switch the agent off for that chat.
7. Every minute, jobs re-queue unanswered chats and expire unpaid orders; every night, one refreshes Instagram tokens.

PayPal is called for real (`api-m.sandbox.paypal.com`); `tests/integration/test_paypal_sandbox.py` runs against the sandbox when `PAYPAL_CLIENT_ID`/`SECRET` are set in `.env`.

## Layout

```
app/
  main.py          API process (lifespan opens the job queue and starts the in-process worker)
  worker.py        standalone worker
  cli.py           operator commands
  core/            settings, database, job queue, encryption, signing, logging, event loop
  webhooks/        Meta webhooks and the webhook inbox
  modules/         business modules: models.py, schemas.py, service.py, tasks.py, router.py
tests/
  unit/            no database
  integration/     real Postgres, built from supabase/migrations
```
