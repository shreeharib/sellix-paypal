# sellix: notes for Claude

Instagram DM assistant plus a Flutter merchant app for small online shops (any product type, not only food).

## Always: keep the handoff

1. **At the start of a session, read [docs/HANDOFF.md](docs/HANDOFF.md)** (what exists, what changed, what is open, how to run and check everything on this PC), then `git status` and `git log -3`.
2. **Before you end a session, and after any large piece of work, update `docs/HANDOFF.md`**: the date, what changed (what, where, why, how it was checked, test counts), new decisions and traps, finished and new open items. Keep it accurate and short; delete stale text. Never put secrets in it.
3. Keep your memory notes in step; they point to the handoff.

## Rules that matter

- Do not commit until the user says so; show the diff first. Never push (the user pushes). Never edit a migration that is already merged: add a new one in `supabase/migrations/`.
- Use the **Bash tool** (PowerShell is blocked here). Run Python through `python -m uv run ...`. Flutter only through `cmd //c 'D:\Android\flutter-direct.cmd <args>' < /dev/null`, never `flutter`/`dart` directly. Details and the Dart-version workaround are in the handoff.
- Write code that contains backslashes (regexes) with the Edit/Write tools, not Bash heredocs: heredocs halve backslashes and silently put backspace characters in the file.
- Before saying "done": `ruff check`, `ruff format --check`, `basedpyright`, `pytest` (backend); `analyze` and `test` (Flutter). Report real output. A prompt, playbook, tool or output-check change also needs the live evals (`evals/README.md`), run twice, plus a row in `backend/app/modules/agent/prompts/CHANGELOG.md`.
- The agent never claims to be human. It doesn't volunteer that it is an AI, but answers honestly if a customer sincerely asks.
- Do not try to get around the company's network controls (Netskope). Do not ask the user for screenshots or images.
- Secrets live in `backend/.env` (gitignored). Never print or write them elsewhere.
