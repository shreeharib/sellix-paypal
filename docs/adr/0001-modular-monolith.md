# 0001: One backend codebase, split into modules

**Status:** accepted · 25 Oct 2026

## Context

A team of 4–5 builds the backend in parallel, under hackathon time pressure, and keeps it as a real product afterwards. Running several services costs money and time; one tangled codebase causes merge conflicts.

## Decision

One Python codebase (FastAPI), run as an API process and a worker process, split into business modules under `backend/app/modules/`. Each module's `service.py` is its only public interface; other modules never touch its tables or internals.

## Consequences

- One deploy and one database: cheap and simple.
- People mostly edit their own modules, so merge conflicts stay rare.
- A module can become its own service later if it really needs to, because its boundary already exists.
