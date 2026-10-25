# Contributing to sellix

The full reasoning is in [docs/dev-plan.md](docs/dev-plan.md). This page is the short version.

## Before you start

1. Pick an issue from the project board (or create one with the **Task** template) and assign it to yourself.
2. Read the plan sections the issue links to.
3. Set up the part you're working on: [backend/README.md](backend/README.md) or [app/README.md](app/README.md).

## Branches and pull requests

- `main` is protected. Create a short-lived branch named `area/short-description`, for example `backend/inventory-holds` or `app/today-screen`.
- Keep pull requests small: aim for under ~400 changed lines. Split big work into steps that each make sense alone.
- Title PRs in conventional style: `feat: …`, `fix: …`, `chore: …`, `docs: …`, `test: …`.
- One approval from the owner of the area (see `.github/CODEOWNERS`) and green CI, then **squash merge** and delete the branch.
- Pull `main` at least once a day, and rebase your branch before asking for review.

## Checks to run before pushing

| Area | Command |
|---|---|
| Backend | `just check`, or in `backend/`: `uv run ruff check . && uv run ruff format --check . && uv run basedpyright && uv run pytest` |
| App | In `app/`: `flutter analyze && flutter test` |

## Rules that prevent merge conflicts

| Thing | Rule |
|---|---|
| Database migrations | Always add a new file in `supabase/migrations/`; never edit one that's already merged |
| Generated Dart API client | Never edit by hand; regenerate after pulling |
| Translation files (`.arb`) | Prefix keys with the feature (`today_…`, `orders_…`) and keep them in alphabetical order |
| Shared enums and order states (`backend/app/core/`) | Change only through a PR reviewed by the commerce owner |
| Lock files (`uv.lock`, `pubspec.lock`) | Never hand-merge; regenerate |
| Prompts and model config | Owned by the AI role; changes need an eval result in the PR |

## Never commit

- Secrets of any kind: `.env` files, API keys, tokens, keystores, Firebase config files. Use `.env.example` for variable names only.
- Real customer data. Test data must be anonymised (names, phone numbers, addresses, IDs, media links).

## Licence and ownership

The project is licensed under [AGPL-3.0-only](LICENSE), and contributions are made under the same licence. Who owns the code is covered by a separate written team agreement (dev plan, section 16).
