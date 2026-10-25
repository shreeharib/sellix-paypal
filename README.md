# sellix

AI sales agents for small merchants who sell through Instagram and WhatsApp DMs. Every morning the merchant tells sellix what's in stock. The agent then answers customers in their own language mix (Tamil + English, Hinglish and so on), takes the order, collects payment through PayPal, and asks the merchant whenever it's unsure. The merchant runs everything from one Flutter app.

> **Status:** early development for the [PayPal AI Hackathon 2026](https://paypalaihackathon.devpost.com/). Judge instructions, the hosted demo and the video will be added here before submission.

## Repository layout

| Folder | What's inside |
|---|---|
| [`backend/`](backend/) | Python (FastAPI) API and worker: webhooks, the AI agent, orders, inventory, payments |
| [`app/`](app/) | Flutter merchant app (Android + web) |
| [`supabase/`](supabase/) | Database migrations and demo seed data |
| [`evals/`](evals/) | Language test set and model bake-off |
| [`docs/`](docs/) | Product plan, development plan, architecture decisions, notes on platform payloads |

## Getting started

**All commands** (setup, database, running, tunnel, operator commands, tests, Flutter, troubleshooting) are in [commands.md](commands.md). The short version:

**Backend** (Python 3.12+ and [uv](https://docs.astral.sh/uv/)):

```bash
cd backend
uv sync
cp .env.example .env
uv run uvicorn app.main:app --reload   # http://localhost:8000/health and /docs
uv run pytest
```

**Flutter app:** see [app/README.md](app/README.md).

**Shortcuts:** with [just](https://github.com/casey/just) installed, run `just --list` (on Windows, from Git Bash).

## Contributing

Read [CONTRIBUTING.md](CONTRIBUTING.md) and the [development plan](docs/dev-plan.md) before your first pull request.

## Licence

[GNU Affero General Public License v3.0](LICENSE) (`AGPL-3.0-only`).
