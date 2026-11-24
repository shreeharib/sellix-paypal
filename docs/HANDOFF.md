# Handoff

The one file a new Claude session reads first. It says what sellix is, what is built, what changed in the
last session, what is open, and how to run and check everything on this PC.

**What to do next is in [NEXT-PHASE.md](NEXT-PHASE.md)** (ordered tasks, decisions waiting on the user, the hackathon deadline).

**Keep it true.** Whoever works on sellix updates this file before ending a session or after any big
piece of work (see [How to keep this handoff](#how-to-keep-this-handoff)). Last updated: **24 Nov 2026**.

---

## 1. What sellix is

**Since 24 Nov 2026 the goal is a real launch** (the PayPal hackathon is over): payments are
**Razorpay**, each shop on its own Razorpay account, and the team will test a release APK on a
phone. What changed that day is section 4; the plan is [NEXT-PHASE.md](NEXT-PHASE.md).

An Instagram DM assistant plus a merchant app for small online shops (food, clothing, jewellery, beauty,
plants, handmade gifts; not only bakeries). Customers message the shop's Instagram account; an AI agent
answers, takes orders (quote card, confirm, payment), and asks the shop owner when it can't decide. The owner
uses a Flutter app (Home, Chats, Stock, Orders, Profile) to set stock, answer questions and see orders.

| Part | Where | Tech |
|---|---|---|
| API, agent, jobs | `backend/` | Python 3.12, FastAPI, SQLAlchemy 2 (async, psycopg 3), procrastinate (jobs in Postgres) |
| Database | `supabase/migrations/*.sql` | Postgres 17; plain SQL files, no migration tracker |
| Merchant app | `frontend/flutter_app/` | Flutter (Riverpod, go_router, dio). `app/` is an older, smaller app: ignore it |
| Evals | `evals/` | Multi-turn scenarios against the real LLM through the simulator API |
| Plan docs | `docs/agent-phase-2.md` (the spec), `docs/agent-final-plan.md` (order of work) | |

**The 24 Nov 2026 work (section 4) is not committed**: about 150 files in the working tree. The
user's rule stands: show the diff, commit only when they say, never push. The paragraph below is
the state before it.

The repo is `D:\Products\sellix`. Work branch **`feat/preorders-and-agent-hardening`** (cut from `feat/flutter-merchant-app` at `961f0ce`; the older branch
holds the same commits). The work of 7 Nov 2026 is committed
(commit `86e4307` by the user: the whole `backend/` folder; then `46a2a39` migrations and deploy config,
`47f9a8a` Flutter app, `ee4fb7d` evals and docs, `b18f382`/the next docs commit, made by Claude at the user's
request) and **pushed to `origin`** (`git@github.com:shreeharib/sellix-paypal.git`). The 8 and 9 Nov work (sections 4.6 to
4.10) is committed as well, in `c3b2994` (9 Nov, 100 files); on 9 Nov the branch matched origin. The user's standing rule:
commit and push only when they say so, show the diff first. `gh` is not installed; `origin` works over SSH from
this laptop. A second remote, `azure`, exists (Azure DevOps): nothing was pushed there. A stray local branch named
`origin/feat/flutter-merchant-app` makes that ref name ambiguous: use `refs/remotes/origin/...` in scripts.

## 2. The user and how they like to work

- Works in a company laptop. Asks for plain-language explanations ("why do we need X?"): explain, then act.
- Wants things verified, not claimed. Report real test output; say what you could not check.
- Cannot share screenshots or images with AI (company policy): never ask for them. Ask them to describe what
  looks wrong in the app.
- Manager-level pressure: a hackathon submission was set for 12 Nov 2026 (demo freeze about 9 Nov).
- **Nothing may be uploaded from this laptop** (24 Nov): no Artifacts, Claude Docs, pushes or other
  outside services. Deliverables stay as local files; give the path.
- Fable 5.2 is blocked by the organisation's admin (403): helpers run on the default model.
- Secrets live in `backend/.env` (gitignored). They were pasted into a chat once: **consider rotating** the LLM,
  PayPal and Instagram secrets before real use. Never write secret values into docs, code or logs.

## 3. How to run and check everything on this PC

PowerShell is blocked by group policy: **use the Bash tool (Git Bash)**. `just` and `uv` are not on PATH.

```bash
# Database (Docker, already running as container sellix-postgres on port 54322)
docker start sellix-postgres        # if stopped
# fresh dev DB from the migrations (deletes data):
docker exec sellix-postgres psql -U postgres -q -c "drop database if exists sellix with (force)" -c "create database sellix"
for f in supabase/migrations/*.sql; do docker exec -i sellix-postgres psql -U postgres -d sellix -q -v ON_ERROR_STOP=1 < "$f"; done

# Backend (from backend/). Port 8000.
python -m uv run uvicorn app.main:app --loop app.core.runtime:new_event_loop
python -m uv run python -m app.cli --help          # create-merchant, issue-token, set-stock, agent-health, ...
python -m uv run python -m app.cli issue-token --merchant-id <id> --minutes 480   # dev token (default 15 min)

# Checks (from backend/). All must pass before saying "done".
python -m uv run ruff check . && python -m uv run ruff format --check . && python -m uv run basedpyright
python -m uv run pytest -q --ignore=tests/integration/test_paypal_sandbox.py     # ~5 min; uses DB sellix_test
```

**Flutter: never run `flutter` or `dart` directly** (it needs PowerShell). Use the launcher, from the project
folder, with `< /dev/null`:

```bash
cd /d/Products/sellix/frontend/flutter_app
cmd //c 'D:\Android\flutter-direct.cmd analyze' < /dev/null
cmd //c 'D:\Android\flutter-direct.cmd test' < /dev/null
```

- **`pubspec.yaml` says `sdk: ^3.13.5` since 24 Nov** (the installed Dart): `pub get`, `analyze`, `test` and
  builds run in the real folder. The old copy at `D:\Android\cache\tmp\sellix_copy` is obsolete.
- Run the web app (port 8080 is what the backend's CORS allows), as its own background task:
  `cd /d/Products/sellix/frontend/flutter_app; cmd //c "D:\Android\flutter-direct.cmd run -d web-server --web-port 8080 --dart-define=DEV_ACCESS_TOKEN=<token> --dart-define=API_BASE_URL=http://localhost:8000" < /dev/null`
  with `run_in_background`. Nesting it in `( ... &)` inside another command dies when that command ends.
- Release builds ignore `DEV_ACCESS_TOKEN`. The release APK is signed with the key in
  `frontend/flutter_app/android/key.properties` (gitignored; password only there) and
  `D:\Android\keys\sellix-release.jks` (made 24 Nov). **Back both up**: every update must be signed
  with the same key. The server address is set at run time on the sign-in screen ("Server"), or built in
  with `--dart-define=API_BASE_URL=https://...`.

| Thing | Value |
|---|---|
| Dev API / web app / eval server | `:8000` / `:8080` / `:8001` |
| Dev shop "Sweet Crumbs" | merchant id `88fa6847-ea60-48d3-9be7-4877c2073130`, agent engine `v2`, DB `sellix` |
| Test DB / temporary DBs | `sellix_test` (pytest recreates it; `TEST_DATABASE_URL` picks another, e.g. one per parallel helper); `sellix_evals`, `sellix_load` are created and dropped by hand |
| Test the agent without Instagram | `http://localhost:8000/simulator` (paste a token), or `POST /v1/simulator/messages` |

### Environment traps (cost us real time)

1. **Backslashes in Bash heredocs are halved.** A Python script that writes a regex like `\bsir\b` into a file ends up
   with a literal backspace character. Write code containing backslashes with the **Edit/Write tools**, or check
   with `grep -c $'\x08' <file>` (must print 0). This bit us five times.
2. A standalone `sleep N` in the foreground is blocked; poll with `for i in $(seq ...); do ...; sleep 5; done`.
3. Long commands that put a detached `&` after a heredoc sometimes fail to parse; split them.
4. `ruff format` can leave `ruff check` complaining once; run check again after format.
5. Foreground commands time out at 10 minutes: use `run_in_background` for evals and servers.
6. **Instagram, graph.facebook.com and api.instagram.com return 403 from this laptop (Netskope).** The Azure LLM
   endpoint works but the connection drops now and then (`RemoteProtocolError`, `ConnectError`). Do **not** try to
   get around Netskope: see section 5.
7. A dev web server left running keeps the token it was started with (`DEV_ACCESS_TOKEN` is a compile-time define; 480 min
   by default), then every call is 401 "Please sign in again". Check the token's `exp` before reusing a server; restart with
   `issue-token --minutes 1440`. Claude may be blocked from killing a leftover server: ask the user to end it
   (`taskkill /PID <pid> /T /F`).
7b. Live evals (needed after any prompt, tool or context change): `docker exec sellix-postgres psql -U postgres -q -c "drop database if exists sellix_evals with (force)" -c "create database sellix_evals"`, run the migration loop into `sellix_evals`, then with `DATABASE_URL` pointing at it: `python -m uv run python -m app.cli create-merchant --name "Eval Bakery"`, `set-stock --merchant-id <id> --file ../evals/demo_stock.json`, `set-agent-engine --merchant-id <id> v2`, `issue-token`. Start the eval server in the background: `PAYMENT_PROVIDER=simulator python -m uv run uvicorn app.main:app --port 8001 --loop app.core.runtime:new_event_loop` (same `DATABASE_URL`), then `python -m uv run python ../evals/run.py --base-url http://localhost:8001 --token <t> ../evals/datasets/scenarios.jsonl ...`. `python -m uv run python -` (script on stdin) and scripts outside `backend/` need `PYTHONPATH=.`.
8. Driving the running web app from here: Chrome headless with `--remote-debugging-port` plus the `websockets` package (in the backend venv) works. Flutter web only exposes buttons after clicking `flt-semantics-placeholder`; set `location.hash` after boot (the URL route is ignored); pass `#/route` with `MSYS_NO_PATHCONV=1` or Git Bash turns it into a path; print with `PYTHONIOENCODING=utf-8` (₹ crashes cp1252). Don't look at screenshots (company policy): compare hashes or read the semantics tree.
9. The user runs commands in **Windows Command Prompt**, not Git Bash. Give them `cmd` syntax (`%VAR%`, `for /f`,
   `cd /d`) or a `.cmd` file; Bash lines pasted into cmd fail.
10. **Line endings and byte checks (9 Nov).** In this Bash, `grep -c $'\r' file` counts every line, so it can't tell CRLF from LF:
    check bytes with Python (`open(f,'rb').read().count(b'\r')`, same for `b'\x08'`). Python's `Path.write_text` on Windows writes
    CRLF: use `write_bytes(s.encode())`. Some files from 8 Nov are CRLF in the working copy; `.gitattributes` (`eol=lf`) normalises
    them on commit, so it is harmless, but an exact-match edit of a CRLF file needs `\r\n` handled.
11. **Never run two `pytest` sessions at once**: both drop and rebuild `sellix_test`, and the first one fails with `AdminShutdown`
    / "database sellix_test does not exist" (9 Nov: 6 false errors in `test_window.py`).
12. **The laptop sleeps during long eval runs.** On wake the job worker runs every missed periodic job at once, and the runner's
    request times out (9 Nov: run 2 died with `TimeoutError` after the night). Re-run the set; after midnight the eval shop also
    needs `set-stock` again (stock is per business day) and a fresh token.
13. `flutter-direct.cmd test ... --plain-name "a name"` crashes ("Illegal character in path") because of the quotes through `cmd`:
    run the whole test file and grep the output instead.
14. **Dart on the web is not the Dart VM**: `<<` and other bit operations give unsigned 32-bit results (`-1 << 31` is
    +2147483648), and ints are JS doubles. Widget tests run in the VM and can't see it; `flutter test --platform chrome`
    hung at "loading" on this PC. Check web-only behaviour with the headless driver (trap 8). Driver details learned on
    9 Nov: set `location.hash` a few seconds after boot and again if the app's start-up moved it to `#/home`; click
    `flt-semantics-placeholder` again after navigating; labels are in `aria-label` or the node's text; tap with CDP
    `Input.dispatchMouseEvent` (moved, pressed, released) at the node's centre.
15. **Helpers (subagents) can die on "SSL certificate verification failed"** talking to the Claude API (the
    company's TLS inspection; 24 Nov, all three at once). Resume each with SendMessage: they keep their context.
    Don't try to get around it.
16. Parallel helpers on the backend must each use their own test database (`TEST_DATABASE_URL=.../sellix_test_b1`):
    a second pytest on `sellix_test` drops it under the first (24 Nov: 160 false failures).
18. **Gradle and memory.** The template's `-Xmx8G` crashed the Gradle daemon (native memory allocation failed; 400 MB free
    of 16 GB). `android/gradle.properties` now uses `-Xmx3G` and in-process Kotlin. A release build takes about 6 minutes; close
    other apps if it crashes again. Delete any `hs_err_pid*.log` it leaves in `android/`.
17. Bash heredocs whose body holds `'''` sometimes fail to parse ("unexpected EOF"). Put the script in a
    scratchpad file and run it with `python -I <file>`.

## 4. What changed on 24 Nov 2026 (Razorpay and launch fixes, not committed)

The API contract for all of this is [api-changes-2026-11-24.md](api-changes-2026-11-24.md). Guides:
[razorpay-setup.md](razorpay-setup.md) (a shop connects Razorpay), [DEPLOY.md](DEPLOY.md) (putting it online).

### 4.0 Razorpay replaces PayPal
- **Each shop connects its own Razorpay account** in the app: onboarding's Payments step or Profile > Payments.
  - The owner pastes a Key ID and Key Secret. `payments.connect_account` checks them with Razorpay (`GET /v1/payments?count=1`), then stores them encrypted (`TOKEN_ENCRYPTION_KEYS`).
  - Storage is the new table `payment_accounts` (migration `20261124000000_razorpay_payments.sql`), along with a webhook secret and webhook address for the shop: `/webhooks/razorpay/<token>`.
  - The bank account lives in Razorpay (the shop's KYC there), never in sellix. Money goes straight from Razorpay to the shop.
  - `RAZORPAY_KEY_ID/SECRET` in `.env` are a shared account, used outside production only, or with `RAZORPAY_SHARED_ACCOUNT_IN_PROD=true` on a one-shop server.
  - Code: `payments/razorpay.py` (HTTP client), `payments/accounts.py`, `payments/service.py`, `api/v1/payments.py`, `webhooks/razorpay.py`.
- **Payment link:** a Razorpay Payment Link (UPI, card, net banking, wallets) for INR orders.
  - `expire_by` is the hold's end, but at least 16 minutes ahead (Razorpay's minimum is 15).
  - The link's notes carry our order id and payment row id.
  - The agent's tool and the v1 engine offer Razorpay first. The shop's plain UPI link is only the fallback, because sellix can't confirm UPI payments.
  - Template `payment_link@3`.
- **An order is paid only through `_apply_link`**, after fetching the link from Razorpay with the shop's keys and checking id, notes, amount and currency. Four things lead there:
  - the return page `/payments/razorpay/return` (its signature is HMAC-SHA256 of `link|ref|status|payment`, checked against Razorpay's own example)
  - verified webhooks, through the inbox and the `process_razorpay_event` job
  - the `settle_open_payments` job, which asks Razorpay about every open link each minute, so webhooks are optional
  - closing links when a shop changes or removes its keys
- **Links end with their order.** The settle job cancels the Razorpay link of an order that expired or was cancelled. A payment that lands anyway is recorded by the late-payment path (`paid` or `paid_stock_short`).
- **A failed try:** the link stays open. About 90 s later (`PAYMENT_FAILED_NOTICE_SECONDS`), if it is still unpaid, code sends `payment_try_again` with the same link, once per order.
- **Refunds:**
  - Razorpay refunds are full and idempotent: the refund request's id is both the `X-Refund-Idempotency` key and the receipt.
  - They settle from Razorpay's answer, the refund webhook (strict match: payment, amount, receipt), or `reconcile_refunds`.
  - Manual payments (UPI the shop saw, cash) are refunded by the shop and only recorded.
  - Fixed an older bug: a restocked refund released *held* stock (taking units from another customer's hold) instead of *sold* stock (`inventory.unsell`).
- **Review fixes** (an independent review, 24 Nov):
  - New keys or a disconnect first cancel the old keys' open links and record any already paid.
  - One order's links are made one at a time (advisory lock).
  - A second payment for a paid order becomes outcome `paid_twice` and asks the owner to refund one.
  - A shop's webhook acts only on that shop's payments, and its dedupe key includes the account.
  - Order payments carry `test_mode`. `RAZORPAY_LIVE_KEYS_ONLY=true` refuses test keys (turn it on when real shops go live).
- **API:**
  - New: `GET/PUT/DELETE /v1/payments/account`, `POST /v1/payments/account/webhook-secret`, `GET /v1/orders/{id}/payments`.
  - The refund answer gains `mode`.
  - `payment_method` is `razorpay|upi|simulator`.
- **Removed:**
  - `payments/paypal.py`, `payments/fx.py`, `webhooks/paypal.py`
  - the PayPal invoice endpoint
  - PayPal settings and tests
  - old rows and constraint values stay valid
- **The simulator stays** (`PAYMENT_PROVIDER=simulator`, never in prod).
- **Tests:** a fake Razorpay at the HTTP level (`tests/integration/fake_razorpay.py`, fixture `fake_razorpay`), `tests/unit/test_razorpay_client.py` (16), `test_razorpay_payments.py` (32), `test_razorpay_chat.py` (2).
- **Not checked against the real Razorpay** (no keys on this laptop yet). Run the checklist in NEXT-PHASE T1 with test keys.

### 4.1 Launch fixes from an audit of the app and backend (24 Nov)
- **New shops start with the assistant off, on v2** (migration `20261124020000`). The first `PUT /v1/onboarding` with `complete: true` switches it on. Test fixtures create shops switched on, and eval set-up needs `set-agent ... on` (evals README).
- **Stock modes are enforced on the server:**
  - `made_to_order` and `unlimited` items are always orderable: up to 99 a line, no hold, shown as `available: 99`. The assistant sees "made to order" or "available" (`context@6`).
  - `inventory` carries its remainder to the current day on first read (`inventory.carry_forward`, safe when two reads race).
  - Units given back on an earlier day's row after the carry go onto today's shelf (`_onto_todays_shelf`).
  - A quote from before midnight is refused after it, so the assistant makes a new one.
  - Order lines record `stock_counted` (migration `20261124010001`).
- **Security:**
  - Restock, sold-out, counter-sale and rollover were writable across shops by variant id. They're now scoped to the shop, with a tenant test on request bodies.
- **Products:** removed with `PATCH is_active:false`; rename keeps the variant; a duplicate name answers 409.
- **Expiry deadlock:** `expire_unpaid_orders` now takes an advisory lock and sorts its batch. The sweep no longer releases holds that belong to orders.
- **Sign-in:**
  - A rotated refresh token reused within 2 minutes gets the session's current pair (migration `20261124020001`).
  - The stored copy is forgotten after the grace (job `forget_rotated_refresh_tokens`).
- **Chats:**
  - A merchant's Instagram reply pauses the assistant for that chat for `AGENT_RESUME_AFTER_MERCHANT_HOURS` (12), then it resumes (migration `20261124020002`).
  - `POST /v1/chats/{id}/messages` sends from the app through the outbox.
  - Chat routes answer under both `/v1/chats` and `/v1/conversations`, with paging.
- **Other endpoints:** `GET/DELETE /v1/rules` (saved "always" answers), `GET /v1/orders/{id}`, `before` paging on orders.
- **Customer names:** a per-minute job fetches new customers' Instagram name and username. This can't be checked from this laptop.
- **Deleting a shop, and privacy:**
  - `DELETE /v1/shop` (owner, typed name).
  - Public `/privacy` and `/data-deletion` pages; their contact line is a placeholder to fill in.
  - Meta's `POST /auth/instagram/data-deletion`: HMAC checked, refused when older than a day, matched on the professional id or the app-scoped id (new column, migration `20261124030000`).
- **Production:**
  - `/docs`, `/openapi.json` and `/simulator` are hidden in prod.
  - `render.yaml` sets prod, payloads off, and `FORWARDED_ALLOW_IPS` set to private ranges (check Render's proxy range on the first deploy).

### 4.2 Checks on 24 Nov
- **Backend:** `ruff`, `ruff format --check` and `basedpyright` are clean. Full suite **637 passed, 0 failed** (10 min 34 s), with every change above in.
- **Flutter:** `analyze` "No issues found!", **455 passed, 20 skipped** (was 402). The app's live contract tests
  (22, including 4 new ones for orders by id, payments, rules and paging) pass against a server on the new code.
- **Release APK built** (24 Nov): `frontend/flutter_app/build/app/outputs/flutter-apk/app-release.apk`, 61.2 MB.
  - Contents: `ai.sellix.sellix_merchant` 0.1.0 (1), label sellix, minSdk 24 / target 36, arm64 + armv7 + x86_64, the adaptive icon.
  - Permissions: INTERNET, POST_NOTIFICATIONS, VIBRATE.
  - Signed with the release key (`apksigner`: CN=sellix, O=sellix, C=IN).
  - No server built in: it opens on sign-in, where "Server" takes the https address.
  - Never run on a phone yet.

### 4.3 The app (24 Nov)
- **Razorpay:**
  - `features/settings/razorpay_card.dart`, used in both Settings > Payments and onboarding. Not connected: a numbered guide with "Open Razorpay sign-up", the Key ID / Key Secret fields with the server's 422/502 text, and a note that sellix never sees bank details. Connected: Test/Live, the key hint, and webhook status. The webhook is folded under "Faster confirmations (optional)".
  - The UPI card is the fallback.
  - Order screen: `GET /v1/orders/{id}` and `/payments`; method, payment id, fee, "Test payment", the open link (copy/share), and Refund with wording by `refund_mode`.
  - PayPal is gone from the app.
- **Server address** at run time: `core/server_config.dart` (SharedPreferences), the "Server" sheet on sign-in and in Profile (https only in release, a Check button that calls `/health`). Changing it signs out.
- **Flaky networks:** `auth_interceptor.dart` signs out only on a real 401 from refresh; offline shows "Can't reach sellix".
- **Android:**
  - Label `sellix`.
  - Release signing from `android/key.properties`; debug signing with a warning if it's missing.
  - `taskAffinity=""` on the auth callback.
  - `POST_NOTIFICATIONS`, desugaring.
  - The sellix logo as an adaptive launcher icon (Android 8+, vector XML from `assets/icons/logo_tile.svg`; older phones keep Flutter's PNG).
  - `build_apk.cmd [https://server]`.
- **Hidden behind `kShowComingSoon = false`** (`core/config.dart`): Google/Apple/email sign-in, "Same as yesterday", timed pause, languages, morning reminder, quiet hours, automations, WhatsApp, photo chips, part refund and more. False texts were fixed. A Terms and privacy link opens `<server>/privacy`.
- **New screens:** "Load older" on Orders and Chats; the chat pause banner with "Turn back on" and a send box; the Rules list with delete; product Remove (with Undo) and Rename; one-day item editing; "Delete my shop".
- **Notifications:** `core/notifications/` polls every 60 s while the app is alive and fires a local notification per new question or paid order; tapping one opens the right screen. Main data refreshes when the app resumes. Permission is asked at the end of onboarding. `flutter_local_notifications` is held at 22.3.2, because 23 needs compileSdk 37 and this PC has SDK platforms 34-36 only.
- The app calls the chat routes under `/v1/conversations/...`; the backend serves both that and `/v1/chats`.

## 4b. Earlier work (7 to 9 Nov 2026)

Everything below is committed and tested. Test totals at the end: **backend 415 passed**, **Flutter 334 passed
(19 skipped, live tests)**, `ruff` and `basedpyright` clean, Flutter `analyze` clean.

### 4b.1 Stock, orders, concurrency
- Stock is a ledger: `daily_stock` has one row per variant per date (`available = opening + restocked - held - sold - counter_sales`, never below 0 by a check constraint). An order holds stock for 15 minutes, `record_payment` turns holds into sales.
- **Fixed a real deadlock**: two customers ordering the same items in opposite order made Postgres abort one. Lines are now locked in variant-id order (`orders/service.py`).
- `tests/integration/test_concurrency.py`: 40 buyers for 10 items sell exactly 10; pre-order days hold the right date; double payment sells once; cancel-vs-pay stays consistent.

### 4b.2 Pre-order availability (backend + app)
- Migration `20261107000000_availability_policy.sql`: `products.available_on` (sold on that one day only) and `products.order_by_date` (last day to order). The total quantity is that day's `daily_stock.opening`.
- `quote()` refuses a one-day item on another day or after its last order date (`catalog.VariantCatalogInfo.ordering_problem`). Customer menus and the agent hide closed items; the merchant still sees them.
- `PATCH /v1/products/{id}` takes `available_on` / `order_by_date` (null clears, omitted keeps). `PUT /v1/stock/upcoming` takes `one_day_only` and `last_order_date`: products it creates become that day's items; a one-day item can't be stocked on another day (422).
- Fixed a contract bug: the app expected `variant_id`, `opening` etc. from `/v1/stock/upcoming` that the API never sent (the Coming days screen would crash). The API sends them now.
- **App**: new `features/stock/day_stock_screen.dart` (route `/stock-for?date=`): set stock for a later day like today's flow (type it, add an item, new product, counts), an "Only on this day" switch and a "Last day to order" picker. The Catalogue tab shows every product with "Only 15 Nov · order by 12 Nov"; today's lists hide other days' one-day items (`StockView.onTodaysList`).

### 4b.3 Production hardening
- **Config** (`core/config.py`, `.env.example`): `DB_POOL_SIZE`, `DB_MAX_OVERFLOW`, `DB_POOL_TIMEOUT_SECONDS`, `DB_STATEMENT_TIMEOUT_MS`, `JOBS_POOL_MAX_SIZE`, `WORKER_CONCURRENCY`, rate-limit settings. Each API process has its own pool; a running agent turn holds one more connection for its lock.
- **Processes**: `backend/Dockerfile` (API default, `python -m app.worker` for the worker), `docker-compose.yml` (db, api with `API_WORKERS`, separate worker), `render.yaml` (API with `--workers 2`, separate worker service). Built and smoke-tested the image (2 server processes answer `/health`); the compose stack and Render blueprint were **not** run end to end.
- **Rate limits** (`core/ratelimit.py`): per signed-in user 240/min, auth endpoints 20/min per address, webhooks 600/min; `/health` exempt. Counted **per API process** (N processes = up to N times the limit); move to Redis for hard limits.
- **Tenant isolation**: `tests/integration/test_tenant_isolation.py` calls every `/v1` endpoint that takes an id as another shop (a guard test fails if a new one isn't listed). It found and we fixed `PUT /v1/stories/posts/{product_id}` letting shop B link to shop A's product.
- **Load test**: `backend/loadtest/` (Locust, `uv add --group load`). Baseline on this Windows laptop, 2 workers, 80 simulated owners, 60 s: ~35 req/s, 0 failures, median 47 ms, p95 ~500 ms (`GET /v1/today` slowest, p95 ~940 ms). Not a production number.
- **Dev tooling**: `issue-token --minutes N` (up to 1440, refused in prod); `agent-health --days N` (turn outcomes, fallback rate, p50/p95, cost, top errors).
- **Locks**: `core/locks.py` Postgres advisory lock; `agent.engine.run_turn` runs one copy of a chat's turn at a time (a redelivered job or the sweeper used to run a second copy and send a contradictory holding message).
- **Model gateway** (`agent/llm.py`): the circuit breaker counts a failed *call* once (after retries), only for service failures (a 400 content-filter refusal no longer counts), opens after 3 within 60 s, 30 s cooldown (was: per attempt, 2 minutes: flagged messages could switch the agent off for a whole shop). Connect timeout 5 s; each model call is also bounded by the turn deadline (60 s, was 30).

### 4b.4 The agent (v2 engine)
How a turn works: `agent/router.py` picks a **playbook** with a small model call (since 9 Nov, section 4.12; the regexes in `context.choose_playbook` are the fallback), `agent/context.py` builds the system prompt from `base.md` + the playbook + `context.md` (shop profile, today's menu, "Coming up" pre-orders with order-by dates, stage, draft, open questions), then `engine._loop` lets the model call tools until `send_reply` passes the output checks (`guardrails/output.py`). Prompts live in `agent/prompts/` with a `CHANGELOG.md` (every prompt change gets a row + an eval result).

Behaviour fixes this session (each has tests and, where useful, a live-eval scenario):
- **Owner answers**: a turn triggered by the owner's answer uses `playbook.owner_answer` (pass the answer on, don't repeat the menu), can't call `ask_shop_owner` again, and a near-repeat of the last reply is rejected. If the model fails entirely the customer gets "Update from the shop: <owner's words>" (`templates/owner_answer_relay.yaml`) instead of the generic holding message.
- **Suggested answers** are data now: migration `20261107010000_escalation_suggested_answers.sql` (`escalations.suggested_answers`), `GET /v1/questions` returns them; the app shows them as chips on the Needs-you card (tap fills the answer sheet) and as buttons in the chat (tap goes to the "Send this?" check). Old questions with the glued-on "Suggested answers:" line are parsed.
- **Voice**: no self-introduction, no "sir/madam" or guessed gender, short, "we" for the shop. **Honesty rule (deliberate)**: the agent never claims to be human; if a customer sincerely asks whether it is a person/bot/AI it says, in one friendly sentence, that it is the shop's virtual assistant and the owner steps in when needed. Code rejects unprompted "I am X's assistant"/"as an AI" and, after one repair attempt, cleans tone slips up (`tidy_style`) instead of falling back.
- **Any kind of shop**: `get_product_details` returns every saved attribute (fabric, size notes, care), not only food fields; routing regexes cover size/colour/fabric/returns/skin; prompts are not food-specific. Not supported: appointment/slot bookings, shipping charges or courier tracking.
- **Greeting vs menu**: a greeting lists no products (`small_talk@3`); "what do you have / anything else" uses the new `playbook.menu` (at most six items, then a narrowing question or the menu photo; plus the open pre-orders, enforced by a soft output check).
- **Pre-orders**: items under "Coming up" are open for booking: the agent says yes and takes the order. `ask_shop_owner` has a `confidence` (0-100; 75+ is sent back once) and a code check sends back plain "is the listed pre-order available?" questions. Both are capped at 2 refusals per turn.
- **Ordering of the chat**: `engine.causal_order` puts each reply right after the message it answered (replies record `trigger_id`), so a customer's "okay" that arrived while a reply was being written isn't answered with the same text again.
- Fallbacks: one open "assistant couldn't finish" question per chat during an outage; none if the agent already asked the owner in that turn. Health words ("eggless") are allowed in a reply that hands the question to the shop after the owner was asked.

### 4b.5 Evals
`evals/run.py` multi-turn runner (new: `owner_answers` turns that answer an open question and wait for the follow-up job; `--seed-preorder` that sets up a "Diwali cake" pre-order). Datasets: `scenarios`, `adversarial`, `owner_answers`, `any_shop` (clothing, jewellery, skincare), `preorders_and_menu`: **40 scenarios**. Every turn is also checked for internal item ids, unfilled `[[tokens]]` and stiff phrases. Final results on the last code: **40/40**, then **39/40** (the miss was a dropped connection to the Azure endpoint, 7 network errors in that run). Run them twice; a language model varies. See `evals/README.md`.

### 4b.6 and 4b.7 PayPal, payment retries, the simulator (8 Nov): superseded
PayPal (and its dollar conversion) was removed on 24 Nov (section 4.0). Still true from that work: the
retry rules (`PAYMENT_MAX_ATTEMPTS`, `PAYMENT_RETRY_COOLDOWN_SECONDS`, the "New payment link" button
`RETRY:<order id>`, used now mainly by the simulator's Reject), the simulator itself
(`PAYMENT_PROVIDER=simulator`, Accept / Reject page, signed webhook, never in prod), the fixed
`event_payment_received` / `event_hold_expired` messages when the model is down, and order references
("#1003") for `cancel_order` / `resend_payment_link`.

### 4b.8 Shop-type templates (8 Nov, committed in `c3b2994`)
- The add-product form follows the shop's type. **Four stock behaviours are fixed in code** (`daily` fresh batches, `inventory` keep until sold, `made_to_order`, `unlimited`); templates only choose among them, and a **shelf life is asked only for `daily`**. Detail fields (size, shade, allergens ...) are data.
- `shop_profile/shop_types.yaml`: `bakery`, `jewellery`, `beauty`, `plants`, `handmade_gifts`, `dress_shop`, `other`. A shop's template is its `shop_type` answer, else the first type whose keywords match its free-text `category` (order in the file matters: "fashion jewellery" is jewellery). Models are in `shop_profile/schemas.py` (`ProductSchema` ...), the lookup is `shop_profile.service.product_schema` / `shop_type_choices` (module boundary rule: other modules import only `service` and `schemas`).
- API: `GET /v1/product-schema` (this shop's template), `GET /v1/shop-types` (`[{id, label}]`); `OnboardingAnswers.shop_type`, kept when a save omits it (a save replaces all other answers).
- To add a shop type: add an entry to the yaml and a row in `tests/unit/test_shop_types.py`. Changing a template never rewrites existing products; bump `version`.
- Demo types are bakery and dress shop; all seven are wired.
- **App** (`frontend/flutter_app`): `ProductSchema` model, `SellixApi.productSchema()` / `shopTypes()`, `productSchemaProvider` (falls back to a built-in schema if the call fails) and `shopSchemaProvider`; `ShopTerms` survives only as the fallback source. The add-product form asks "How do you stock this?" from the schema's stock modes (hidden when a type allows one) and shows shelf life only for fresh batches (`StockTypeQuestion` in `stock_widgets.dart`, replacing `ShelfPicker`); detail inputs (chips with "Other", or one line) come from `detail_fields` and are saved as product `attributes`. The Settings shop-type picker lists `GET /v1/shop-types` and saves `shop_type` plus `category` (the type's label); `OnboardingAnswers` carries `shopType` through every save. The onboarding stock step uses the schema and no longer re-sends an untouched row's stock type (it used to rewrite products to daily). `StockRow.stockMode` is nullable so the catalogue wins when a row lacks it. A new product added from "Set today's stock" now appears in the list without a reload. A typed stock line for an unknown product with no price asks for the price instead of showing the API error. The order screen shows the server's 409 text for payment-link retries ("Wait 40 seconds ...") and a debug assertion in "Try again" was fixed.
- Not done in the app: the onboarding first step still picks from the app's own category table (it keeps `shop_type` when the category is unchanged and clears it when it changes); one-day (pre-order) items still can't be edited; the "+" report is unresolved (section 7).

### 4b.9 UI vs backend audit and fixes (8 Nov)
A read-only audit compared every Flutter API call with the backend OpenAPI. Fixed: `/v1/today` stock rows now carry `stock_mode` and `shelf_life_days` (the app defaulted a missing one to "daily", and the onboarding stock step re-sent it, silently rewriting products); `POST /v1/today/parse-stock-text` now needs sign-in; the orders `payment_status` filter accepts `unpaid`. Open items are listed under "Found on 8 Nov".

**Checks run on 8 Nov:** backend 470 passed, `ruff` and `basedpyright` clean, the 4 real PayPal sandbox tests pass; Flutter `analyze` clean and 400 passed (20 skipped live tests); the app's live contract tests (18, `test/api/live_contract_test.dart`, run with `LIVE_API_URL` and `LIVE_TOKEN` against a server on the new code) all pass, so the app parses every real answer including `/v1/product-schema`. Live evals (real model): the first run was 29/31 and caught that `playbook.payment_problem` still told the model to ask the owner to cancel (`cancel_order` itself worked); after `payment_problem@2` the main set (scenarios, adversarial, any_shop) was 31/31 twice and owner answers + pre-orders 11/11. Not checked: the new screens in a real browser (nobody has looked at them), a real sandbox buyer paying with the converted dollar amount, and the simulator pages by eye.

### 4b.10 Typed "ok" no longer orders; off-topic routing; no "sir / madam" (9 Nov, committed in `c3b2994`)
- **Confirming an order** (`agent/affirmation.py`): a typed reply places an order only when it clearly asks for it. Strong words
  (`_STRONG`): confirm, place the order, book it, go ahead, and Tamil / Hindi equivalents (confirm pannunga, order podunga,
  uruthi / உறுதி, order kar do, book karo, ऑर्डर कर). A plain acknowledgement (`_WEAK`: ok, okay, sure, yes, fine, done, seri,
  haan, theek, 👍, சரி, हाँ ...) is `unclear` **without** a model call, and `confirm_order` tells the model to answer what was
  asked, then point to the Confirm button. A strong word next to a question or "wait / not yet / later" (`_HOLD`) goes to the
  model; `classifier.affirmation@2` says acknowledgements and questions are `unclear`. The Confirm tap is unchanged (code, no
  model). `playbook.new_order@5` and `tool.confirm_order@2` say the same. The word list was proposed in NEXT-PHASE and used as
  is: the user can still change it (`_STRONG` / `_WEAK`, with a row in `tests/unit/test_affirmation.py`).
- **Off-topic** (`agent/context.py`): `_OFF_TOPIC` (code like `print(`, "write a program", Armstrong / Fibonacci, homework,
  maths-only messages, jokes, poems, trivia such as "capital of", politics, weather) and `_ABUSE` (insults; not "stupid" or
  "dumb", customers say "dumb question, but") route to `playbook.abuse_or_off_topic@2` just before the `new_order` fallback.
  The playbook declines in one line and offers the shop, still answers a sincere "are you a bot?" honestly, helps with any shop
  part of the message, and hands abuse to the owner. Mid-order, routing keeps `new_order`; `base@4` hard rule 7 is the backstop.
  The phrases are narrow on purpose ("dress code", "floral print", "loyalty program for", "what day is it" stay on-topic).
- **Persona** (`shop_profile.service.render_profile`): `intro` and `address_customers` are no longer written into the profile
  (the fields stay in the schema so older app builds can still save). The app no longer asks for them: the onboarding talk step
  (`ob_talk_screen.dart`) and Settings > Shop profile > How sellix talks lost "Call customers" (Sir or madam / By name /
  Akka / anna) and "How sellix introduces itself"; both now clear the two answers on save and show a note ("I use a customer's
  name only if they give it ... If a customer asks, I say I'm your shop's virtual assistant"). The preview has no "madam".
  **Sweet Crumbs' profile was re-saved in dev DB `sellix`: v5** (v4 kept). The honesty rule (`base` rule 6) is unchanged.
- **"+" did nothing in the web app: fixed** (`features/stock/stock_widgets.dart`, `WhyStockRow`). The row passed
  `min: -1 << 31` to `SxStepper` to mean "no limit". In the Dart VM (tests) that is -2147483648, but **on the web Dart's
  bit shifts are unsigned 32-bit, so it was +2147483648**: every + was below the "minimum" and the stepper refused it
  with no message. That is why every widget test passed. Now `min: widget.min - 1` (one step below the row's minimum
  reaches the row, which shows the reason). It broke every `WhyStockRow`: "What did you make today?" (`#/morning`),
  "How many do you have now?" in Add product, the day-stock screen. Reproduced and checked in a real browser with the
  headless driver on `#/morning`: "Count of Brownie" stayed 0 after a tap before the fix, went 0 to 1 after. The
  Add product count uses the same widget but was not driven by hand. New test pins the stepper's `min` (fails on the
  old line: -2147483648). Also: the count is one `Semantics` node ("Count of Brownie", value, live region), so
  screen readers announce it and the driver can read it.
- **"Ready for pickup" now reaches the customer** (user report 9 Nov, order #1004: the app changed the order, the
  customer heard nothing; the feature had never been built). `PATCH /v1/orders/{id}/status` calls
  `conversations.after_status_change` after its commit: code (not the model) queues a fixed template in the customer's
  language and schedules delivery at once. `ready` + pickup: `order_ready_pickup`; `ready` + delivery / courier:
  `order_packed`; `delivered`: `order_delivered`; `completed` + digital: `order_sent`. Accept and "picked up" send
  nothing. One message per order and status (outbox key), so the app's undo and redo doesn't send twice; but an undo
  can't take back a message already sent. A failure to queue it is logged and never fails the status change. Test:
  `tests/integration/test_order_status_messages.py` (through the real endpoint and outbox). Tamil / Hindi lines of
  the four templates need a native speaker.
- **Checked:** backend **521 passed** (470 + 51 new), `ruff`, `ruff format --check`, `basedpyright` clean; Flutter `analyze`
  clean, **402 passed** (20 skipped). Live evals: 9 Nov, main set (scenarios, adversarial, any_shop; 37 scenarios): 36/37, 37/37, 37/37. The one miss was the scenario's own check, not the agent: after "when can I pick it up?" the agent had asked the owner, so "okay" was answered as an acknowledgement of that, with no order placed; the turn now checks that no order is placed instead of requiring the word "confirm". Owner answers + pre-orders: 11/11 twice. The only fallback turns were Azure's content filter on the "ignore all your rules" message (as before).

### 4b.11 Agent harness explainer page (9 Nov)
- **`docs/agent-harness.html`**: one page that explains the backend agent end to end (webhook, inbox, turn job, the engine loop, the 20 tools, the 11 playbooks and how one is chosen, how context is built, memory, stages, guardrails, duplicate protection, the owner loop, payments, engine modes, evals, status, interview questions). Written from the code at `c3b2994`, with status taken from this file. Also published as a private claude.ai artifact for sharing: https://claude.ai/artifact/Y9tLyWixaQYSP8sP3dLiSy (publish the same file again to update that link).
- **`docs/conversation-trace.html`** (companion, private artifact https://claude.ai/artifact/6J1rVtck3vFX29c6rjMuYo): one example chat (2 chocolate cookies, pickup, add a brownie, "Perfect, place the order", PayPal payment) drawn as sequence diagrams of the calls in order (API, worker, Postgres, engine, tools, model), with the playbook, tools, stage and the Postgres rows changed after each of its 5 turns. The playbook for each message, the confirmation result, the quote cards and the payment message were produced by the real functions and templates; ids, prices and wording are examples. The diagrams were generated by a throwaway script in a session scratchpad (not in the repo): edit the HTML directly.
- Checked: the tools per stage and the prompt counts were printed by importing `registry.TOOLS` and the prompt store; the page's JavaScript copy of `choose_playbook` and `affirmation.classify` gave the same answers as the Python on 58 messages (headless Chrome). No code changed, so no tests or evals were run.
- **Found, not fixed:** (1) (addressed by the router, section 4.12; the fallback rules still have the gap) "what else do you have" never routes to `playbook.menu` (`_MENU` matches "anything else", not "what else"): it gets `new_order` in browsing and `payment_problem` while paying. (2) Draft mode holds only `send_reply`'s message; the quote card, payment link and templates that tools queue go out at once. (3) `lookup_story` and `describe_image` have `writes = False` but save their vision results, so shadow mode writes that cache. (4) New merchants default to `agent_engine = 'v1'` (migration default).

### 4b.12 The playbook is chosen by a model call (9 Nov, committed in `0fbb63a`)
The user asked for this: regex routing can miss what a message is about. How it works now:
- **`agent/router.py`** (`router.choose`): the owner's answer gets `owner_answer` with no call (it is an event, not words). Otherwise one `llm.complete` call (JSON) with the system prompt **`prompts/router/playbook.md`** (`router.playbook@1`: the stage, a story/attachment flag, every playbook except `owner_answer` with its `applies_when` line, and how-to-choose rules) and one user message: the last 6 messages as `Customer: … / Shop: … / Shop owner: … / [Shop event: payment_received #1004]`, each cut to 400 characters. The answer must be `{"playbook": "<name>"}` naming an offered playbook.
- **Fallback**: an error, a timeout (`AGENT_ROUTER_TIMEOUT_SECONDS`, 15 s), bad JSON or an unknown name → `context.choose_playbook` (the old regexes, unchanged). `AGENT_PLAYBOOK_ROUTER=rules` uses the rules only (the test settings do this, so scripted tests never make a real router call). `LLM_ROUTER_MODEL` sends the call to another model (`llm.complete(..., model_chain=...)`, new).
- **Each playbook file has an `applies_when` header line** (the prompt store already allowed the key; it now keeps it: `prompt_store.applies_when`, `prompt_store.ids`). Playbook bodies and versions are unchanged. Changing an `applies_when` line changes the router's prompt: bump `router.playbook`.
- **Engine** (`engine.py`): `_load` no longer builds the prompt; `_run_turn` runs the inbound gate first, then `_prepare` routes and builds (`_turn_context` + `_context` replace `_build`). So gated turns make no router call. The choice is stored at once (`tracing.set_playbook`, and `Trace.playbook` is read back on resume), so a resumed turn keeps its playbook and doesn't call the router again. The router call is a `turn_steps` row (kind `model`, step `-2`, key `<turn>:router`), so its tokens and cost count in the turn and `model_calls` includes it; `tracing.first_step` (for `replay-turn`) skips it. `replay_turn` routes with today's router. `context.build` takes the `playbook` (and no longer the trigger).
- **Behaviour change to know:** shop-event turns (payment received, hold expired) are told to use `order_status`; before, they got whatever the last customer message routed to. Mid-order messages still default to `new_order` (router rule), but a clear complaint or a pure product question mid-order can now get its own playbook.
- Cost and latency: one extra short model call per ungated turn. With a slow reasoning model as `LLM_MODEL` it adds seconds; set `LLM_ROUTER_MODEL` to a fast model if the eval latency shows it.
- **Checked:** new tests first (they failed on the missing module): `tests/unit/test_playbook_router.py` (17: the "what else" case, prompt contents and the customer kept out of the system prompt, the 6-message window, events, the owner answer without a call, fallbacks for errors, bad answers, timeouts, the rules setting, the router model setting), a gateway test for `model_chain`, and 3 integration tests in `test_agent_v2.py` (the router's choice drives the prompt and is recorded with its cost; a resumed turn keeps its playbook; a gated turn never calls the router). `ruff`, `ruff format --check`, `basedpyright` clean; full backend suite **542 passed** (521 + 21 new). **Live evals (9 Nov, real model, throwaway DB `sellix_evals`, dropped after):** main set 37/37 twice; owner answers + pre-orders 10/11 then 11/11 (the miss: two Azure `ConnectTimeout`s in one scenario, both turns sent the holding message; the router had picked the right playbooks). Router over both runs: 150 model answers, all valid, spread over 10 playbooks; 3 fell back to the rules (1 content filter, 2 network). **Cost: 3.7 s average per router call (6.6 s p95, 9.2 s max) on the configured model**; `LLM_ROUTER_MODEL` with a fast model would cut that.
- The two explainer pages (`docs/agent-harness.html` §5, `docs/conversation-trace.html`) still describe regex routing.

## 5. Decisions and why (don't undo without asking)

| Decision | Why |
|---|---|
| The agent won't deny being an AI to a sincere question | Deception, and some jurisdictions require disclosure. It just doesn't volunteer it |
| We don't get around Netskope | It's the company's security control. Real fixes: ask the network team to allow `www.instagram.com`, `api.instagram.com`, `graph.instagram.com`, `graph.facebook.com`; or run the backend somewhere outside the company network (cloud). Moving the login to the phone would not help: the server also calls Meta's API (token exchange, sending DMs), and the app secret must never go into the app |
| One-day items are an explicit `one_day_only` flag, not inferred | A new product with tomorrow's stock could be a special or a regular item starting tomorrow |
| A small model call picks the playbook; the regex rules are only the fallback (9 Nov, the user's decision) | Regex missed real messages ("what else do you have" never reached `menu`). The owner's answer stays code-routed (it is data). Costs one short model call per ungated turn; `AGENT_PLAYBOOK_ROUTER=rules` switches back, `LLM_ROUTER_MODEL` can use a cheaper model |
| Rate limits are in memory | Good enough to stop runaway clients; use Redis for hard guarantees |
| Each shop uses its own Razorpay account; bank details stay in Razorpay (24 Nov) | Money goes straight from Razorpay to the shop; sellix collecting for many shops in one account would need an RBI payment-aggregator licence. Launch with pasted API keys plus an in-app guide (user's choice, 24 Nov); apply for Razorpay Partner so a later "Connect with Razorpay" button replaces the keys. Route (bank details typed in sellix) was considered and not chosen |
| Payments confirm by polling as well as webhooks | Most small shops won't set up a webhook; asking Razorpay about open links each minute makes the webhook an optimisation, not a requirement |
| A failed Razorpay try is told to the customer only after ~90 s, once per order | The link stays open and most people retry on Razorpay's page at once; an instant "it failed" next to a success confuses |
| New shops start with the assistant off; finishing onboarding switches it on (24 Nov) | Before, the bot answered real DMs right after the first sign-in, with an empty profile. Draft mode stays available from the CLI; it needs push notifications to be workable |

## 6. Where things are

- Agent: `backend/app/modules/agent/` (`engine.py` loop and fallbacks, `context.py` routing and prompt build, `tools/`, `guardrails/output.py`, `llm.py`, `prompts/`).
- Orders and stock: `backend/app/modules/{orders,inventory,catalog}/service.py`. Payments: `modules/payments/`.
- API: `backend/app/api/v1/`. Jobs: `core/jobs.py`, each module's `tasks.py`. Locks/limits: `core/locks.py`, `core/ratelimit.py`.
- Tests: `backend/tests/{unit,integration}/` (integration builds a fresh DB from the real migrations).
- Flutter: `frontend/flutter_app/lib/{core,design,features}/`; tests in `test/` (fake API in `test/support/fake_sellix_api.dart`).

## 7. Open items, risks, what to do next

The ordered plan is [NEXT-PHASE.md](NEXT-PHASE.md). In short:

**Needs the user**
1. Review the diff and say when to commit (about 150 files; nothing is committed).
2. Razorpay test keys, to run the live checklist (NEXT-PHASE T1). Later: apply for Razorpay Partner.
3. Where the backend runs (DEPLOY.md). The phone app can't work against this laptop.
4. Fill in the contact line on `/privacy` and `/data-deletion` (placeholder `[CONTACT EMAIL: ...]`).
5. Rotate the LLM, Instagram and old PayPal secrets that were once pasted into a chat.
6. Whether to run the live AI evals: they send test chats to the configured model. Needed after `context@6` and the payment tool change; not run on 24 Nov.

**Open, not done**
- **No push notifications.** The app polls while it is alive. FCM needs a Firebase project and `google-services.json`.
- **Meta:**
  - App Review and business verification before real shops.
  - The deletion callback's id is unconfirmed: it may be the app-scoped id; both are matched now.
- **Not deleted with a shop:** `webhook_events` raw payloads hold message text and aren't deleted with a shop. They need a retention job.
- **v1 prompts:** the v1 engine's `customer_agent.md` still says "N left" for made-to-order items. New shops use v2.
- **Made-to-order and future dates:** `registry.stock_on(day)` only knows days with stock rows, so the assistant can't take a made-to-order order for an arbitrary later date (the server would accept it).
- **Native speakers:** Tamil and Hindi lines of `payment_link@3` and `payment_try_again@1` (and the older templates) need a native speaker.
- **Still open from earlier (section 4b):**
  - the global order numbers
  - the onboarding test chat holding real stock
  - in-memory rate limits
  - the remaining "not active yet" features: voice, photo, WhatsApp, cash on delivery, share link, plan and billing

## How to keep this handoff

**This is a standing instruction for every Claude session on this repo** (also in `CLAUDE.md`, which Claude Code loads automatically).

1. **Start of a session:** read this file, then `git status` and `git log -3`. Trust the code over this file if they disagree, and fix the file.
2. **During:** when you decide something that isn't obvious from the code (a rule, a trade-off, a thing you refused to do and why), add a row to section 5.
3. **Before you end a session, or after any large piece of work:** update this file. Change the date; move finished items out of section 7; add what changed to section 4 (what, where, why, how it was checked, the test counts); add new traps to section 3; list new open items and decisions needed. Keep it accurate and short enough to read in a few minutes: delete stale text, don't pile on.
4. **Never put secrets** (keys, tokens, passwords, customer data) in this file.
5. If you create or change a migration, a command, a port or a workaround, say so here.
6. Also keep the memory notes (`MEMORY.md`) in step: the memory points here.
