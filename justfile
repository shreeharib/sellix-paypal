# Common commands: `just --list`. Install just: https://github.com/casey/just
# On Windows, run just from Git Bash (the recipes use bash).
set windows-shell := ["bash", "-cu"]

default:
    @just --list

# Install backend dependencies
setup:
    cd backend && uv sync

# Start local Postgres in Docker on port 54322 (skip if you use `supabase start`)
db-up:
    docker start sellix-postgres 2>/dev/null || docker run -d --name sellix-postgres -e POSTGRES_PASSWORD=postgres -p 54322:5432 postgres:17-alpine

# Recreate the local dev database from supabase/migrations (deletes its data)
db-reset:
    docker exec sellix-postgres psql -U postgres -q -c "drop database if exists sellix with (force)" -c "create database sellix"
    for f in supabase/migrations/*.sql; do docker exec -i sellix-postgres psql -U postgres -d sellix -q -v ON_ERROR_STOP=1 < "$f"; done

# Run the API (with the job worker inside) and reload on code or .env changes
dev:
    cd backend && uv run uvicorn app.main:app --reload --reload-include .env --loop app.core.runtime:new_event_loop

# Run the job worker on its own (when RUN_WORKER_IN_PROCESS=false)
worker:
    cd backend && uv run python -m app.worker

# Operator commands, e.g. `just cli create-merchant --name "Sweet Crumbs"`
cli *args:
    cd backend && uv run python -m app.cli {{args}}

# Format and auto-fix the backend code
fmt:
    cd backend && uv run ruff format . && uv run ruff check --fix .

# Run every backend check that CI runs
check:
    cd backend && uv run ruff check . && uv run ruff format --check . && uv run basedpyright && uv run pytest

# Run backend tests (extra arguments go to pytest, e.g. `just test -k meta`)
test *args:
    cd backend && uv run pytest {{args}}
