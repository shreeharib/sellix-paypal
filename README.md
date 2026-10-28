# sellix: Omnichannel Enterprise AI Commerce SaaS

**sellix** is an omnichannel enterprise AI sales and commerce platform designed for D2C brands, makers, cloud kitchens, and merchants selling across **Instagram DMs, WhatsApp Cloud API, and Counter POS**.

Powered by autonomous multi-lingual AI sales agents, sellix answers customers in their natural language mix (Tamil + English, Hinglish, Tanglish, and more), references a multi-mode inventory ledger (daily perishable, perpetual inventory, made-to-order, unlimited, serialized), manages stock reservations with sub-second concurrency, settles payments across dual rails (PayPal and direct UPI), and escalates exceptions to merchant management apps.

> **Architecture Standard:** **Omnichannel Enterprise SaaS**. The platform is designed from the ground up for multi-channel commerce, multi-category catalogs, multi-tenant horizontal scaling (PostgreSQL with Citus-ready sharding), and an orthogonal triple-status order lifecycle (`status`, `payment_status`, `fulfilment_status`).
>
> **Status:** Active development for the [PayPal AI Hackathon 2026](https://paypalaihackathon.devpost.com/) and production deployment. Judge instructions, the hosted demo, and video walkthrough are linked here.


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
