# sellix commands

Every command you need to set up, run, test and debug sellix locally. Run them from the **repo root** unless a block says otherwise. On Windows, use **Git Bash**.

| Service | Address |
|---|---|
| API (FastAPI) | http://localhost:8000 · docs at http://localhost:8000/docs |
| Merchant web app (Flutter) | http://localhost:8080 |
| Postgres (Docker) | `localhost:54322`, user `postgres`, password `postgres`, database `sellix` |

> **Two Windows notes for the team's managed laptops**
> - **uv:** if `uv` isn't on your PATH (it was installed with pip), use `python -m uv` everywhere this page says `uv`.
> - **Flutter:** group policy blocks `flutter.bat`. Use the launcher `D:\Android\flutter-direct.cmd` wherever this page says `flutter`. From Git Bash: `cmd //c 'D:\Android\flutter-direct.cmd' <command> < /dev/null`.

---

## 1. First-time setup

```bash
# Backend dependencies (creates backend/.venv)
cd backend && uv sync && cd ..

# Settings: copy the template, then generate the secrets and paste them into backend/.env
cp backend/.env.example backend/.env
cd backend && uv run python -m app.cli generate-secrets && cd ..
```

Then fill in the rest of `backend/.env` from the team password manager: Instagram app ID and secret, LLM endpoint and key, PayPal sandbox keys.

```bash
# Flutter packages (also generates the English/Tamil text code)
cd app && flutter pub get && cd ..
```

Optional: install [just](https://github.com/casey/just) for the shortcuts below (`pip install --user rust-just` works too). `just --list` shows them all.

---

## 2. Database

```bash
just db-up      # start Postgres in Docker (container "sellix-postgres", port 54322)
just db-reset   # recreate the "sellix" database from supabase/migrations (deletes its data)
```

Without just:

```bash
docker start sellix-postgres 2>/dev/null || docker run -d --name sellix-postgres -e POSTGRES_PASSWORD=postgres -p 54322:5432 postgres:17-alpine

docker exec sellix-postgres psql -U postgres -q -c "drop database if exists sellix with (force)" -c "create database sellix"
for f in supabase/migrations/*.sql; do docker exec -i sellix-postgres psql -U postgres -d sellix -q -v ON_ERROR_STOP=1 < "$f"; done
```

**Apply only a new migration** (keeps your data):

```bash
docker exec -i sellix-postgres psql -U postgres -d sellix -v ON_ERROR_STOP=1 < supabase/migrations/<new-file>.sql
```

**Open a SQL prompt:** `docker exec -it sellix-postgres psql -U postgres -d sellix`

---

## 3. Run the backend

```bash
just dev
# or
cd backend && uv run uvicorn app.main:app --reload --reload-include .env --loop app.core.runtime:new_event_loop
```

- The **job worker runs inside the API** (`RUN_WORKER_IN_PROCESS=true`): webhooks, agent replies, order expiry and token refresh all work with just this one process.
- `--loop app.core.runtime:new_event_loop` is needed on Windows only.
- On Windows, auto-reload can get stuck when the server runs in the background. If code changes don't show up, stop it and start it again.

**Separate worker** (only when `RUN_WORKER_IN_PROCESS=false`): `just worker`, or `cd backend && uv run python -m app.worker`.

**Is it up?**

```bash
curl http://localhost:8000/health                       # {"status":"ok",...}
curl -o /dev/null -w "%{http_code}\n" http://localhost:8000/v1/today   # 401 = API up, login required
```

The startup log warns about any required settings still missing from `.env`.

---

## 4. Public URL for Meta and PayPal (tunnel)

Instagram and PayPal webhooks, and the Instagram login redirect, need a public HTTPS address.

```bash
docker rm -f sellix-tunnel 2>/dev/null
docker run -d --name sellix-tunnel cloudflare/cloudflared:latest tunnel --no-autoupdate --url http://host.docker.internal:8000
docker logs sellix-tunnel 2>&1 | grep -oE 'https://[a-z0-9-]+\.trycloudflare\.com' | head -n 1
```

Then:

1. Put the URL in `backend/.env` as `PUBLIC_BASE_URL=` and restart the backend.
2. Register it (the URL changes every time the tunnel restarts):
   - **Meta → webhooks:** `<URL>/webhooks/meta`, verify token = `META_VERIFY_TOKEN` from `.env`
   - **Meta → OAuth redirect URI:** `<URL>/oauth/instagram/callback`
   - **PayPal app → webhook:** `<URL>/webhooks/paypal`, then copy its ID into `PAYPAL_WEBHOOK_ID`

**Check the tunnel:**

```bash
curl --ssl-no-revoke "<URL>/webhooks/meta?hub.mode=subscribe&hub.verify_token=<META_VERIFY_TOKEN>&hub.challenge=ok"   # prints: ok
```

(`--ssl-no-revoke` is only needed behind the company proxy.)

---

## 5. Set up a merchant (operator commands)

Until onboarding lives in the app, operators use these. The `cli` recipe forwards everything after it:

```bash
just cli --help
just cli create-merchant --name "Sweet Crumbs"                         # prints the merchant ID
just cli set-shop-profile --merchant-id <id> --file shop.md            # Markdown: hours, policies, FAQs
just cli set-stock --merchant-id <id> --file stock.json                # today's items (format below)
just cli set-stock --merchant-id <id> --file stock.json --date 2026-11-01 --until 2026-11-05   # the same stock each day (pre-orders)
just cli connect-instagram --merchant-id <id>                          # prints the link to open
just cli set-agent --merchant-id <id> off                              # or: on
just cli resume-conversation --conversation-id <id>                    # agent back on for one chat
just cli generate-secrets                                              # fresh values for .env
just cli set-agent-engine --merchant-id <id> v2                        # v1 | v2 | shadow | draft
just cli shadow-report --merchant-id <id> --days 1                     # v1 replies next to v2's
just cli replay-turn --turn-id <id>                                    # re-run a v2 turn's model call
just cli issue-token --merchant-id <id>                                # token for the simulator/evals
```

**Simulator:** open http://localhost:8000/simulator, paste a token from `issue-token`, and chat with the shop's assistant through the real pipeline (nothing is sent to Instagram).

Without just: `cd backend && uv run python -m app.cli <command> ...`

`stock.json` format (price in rupees/dollars; currency defaults to INR; PayPal needs e.g. USD):

```json
[
  {"product": "Scoop cookie", "variant": "Chocolate", "price": "60", "quantity": 10},
  {"product": "Gift box", "variant": "Chocolate", "price": "12.50", "quantity": 5, "currency": "USD"}
]
```

Merchants who sign in with **"Continue with Instagram"** in the app get their shop created automatically; the commands above are for support and testing.

---

## 6. Test the backend

```bash
just check            # everything CI runs: lint, format check, types, tests
just test             # tests only
just test -k orders   # only tests whose name matches "orders"
```

Without just (from `backend/`):

```bash
uv run ruff check .            # lint
uv run ruff format .           # format (use --check to only verify)
uv run basedpyright            # types
uv run pytest                  # all tests
uv run pytest tests/unit       # fast tests, no database
uv run pytest -x -q            # stop at the first failure, quiet output
```

- **Database tests** need Postgres on port 54322 (`just db-up`). They build their own `sellix_test` database from the migrations and skip themselves if Postgres is down. To make that a failure instead (as CI does): `REQUIRE_DB_TESTS=1 uv run pytest`.
- **PayPal sandbox tests** call the real PayPal sandbox with the keys in `.env` (they skip without them):

```bash
uv run pytest tests/integration/test_paypal_sandbox.py -v
```

---

## 7. Run and test the Flutter app

From `app/` (remember: `flutter` = `D:\Android\flutter-direct.cmd` on the managed laptops):

```bash
flutter pub get                 # packages + generated English/Tamil text
flutter analyze                 # lint and type checks
flutter test                    # widget tests
```

**Run on the web** (the API must allow this origin: `WEB_APP_ORIGINS=http://localhost:8080`):

```bash
flutter run -d chrome --web-port 8080 --dart-define=API_BASE_URL=http://localhost:8000
```

**Or build once and serve the release build:**

```bash
flutter build web --release --dart-define=API_BASE_URL=http://localhost:8000
python -m http.server 8080 --bind 127.0.0.1 --directory build/web
```

**Android** (phone with USB debugging, or an emulator):

```bash
flutter devices
flutter run -d <device-id> --dart-define=API_BASE_URL=<public API URL>
flutter build apk --debug --dart-define=API_BASE_URL=<public API URL>   # APK in build/app/outputs/flutter-apk/
```

A phone can't reach `localhost` on your laptop: use the tunnel URL from section 4. Sign-in needs `sellix://auth/callback` in the API's `APP_REDIRECT_URIS`.

---

## 8. Stop everything

```bash
# Backend: Ctrl+C in its terminal. If it's stuck in the background, find and stop it:
netstat -ano | grep ":8000 .*LISTENING"      # last column is the process ID
taskkill //PID <pid> //F

docker stop sellix-tunnel sellix-postgres    # tunnel and database (data is kept)
```

---

## 9. When something goes wrong

| Symptom | Check |
|---|---|
| `404` on a route that should exist | The server is running old code. Restart it (section 3). |
| Webhooks never arrive | Is the tunnel up and `PUBLIC_BASE_URL` current? `docker logs sellix-tunnel`. Re-register the URL in Meta/PayPal after a tunnel restart. |
| `401 Invalid signature` on webhooks | `META_APP_SECRET` / `INSTAGRAM_APP_SECRET` (Meta) or `PAYPAL_WEBHOOK_ID` (PayPal) doesn't match the app that sent it. |
| Agent doesn't reply | Is the agent on (`just cli set-agent ... on`) and the chat not paused (`resume-conversation`)? Look for `escalation.opened` or `conversations.send_failed` in the server log. |
| Web app shows "Can't reach sellix" | API down, wrong `API_BASE_URL`, or `WEB_APP_ORIGINS` missing the app's origin. |
| `curl: (35) ... revocation` | Company proxy: add `--ssl-no-revoke`. |
| Database tests "skipped" | Postgres isn't running: `just db-up`. |
| `Unable to determine engine version` (Flutter) | You ran `flutter.bat`; use `D:\Android\flutter-direct.cmd`. |
