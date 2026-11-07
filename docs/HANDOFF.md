# Handoff

The one file a new Claude session reads first. It says what sellix is, what is built, what changed in the
last session, what is open, and how to run and check everything on this PC.

**Keep it true.** Whoever works on sellix updates this file before ending a session or after any big
piece of work (see [How to keep this handoff](#how-to-keep-this-handoff)). Last updated: **7 Nov 2026**.

---

## 1. What sellix is

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

The repo is `D:\Products\sellix`. Branch **`feat/flutter-merchant-app`**. The work of 7 Nov 2026 is committed
(commit `86e4307` by the user: the whole `backend/` folder; then `46a2a39` migrations and deploy config,
`47f9a8a` Flutter app, `ee4fb7d` evals and docs, made by Claude at the user's request). `46a2a39`, `47f9a8a`
and `ee4fb7d` are **not pushed**; the user pushes. The user's standing rule: commit only when they say so, show
the diff first, never push. `gh` is not installed. Note `86e4307` has the backend code but not its migrations
(they are in `46a2a39`): push them together.

## 2. The user and how they like to work

- Works in a company laptop. Asks for plain-language explanations ("why do we need X?"): explain, then act.
- Wants things verified, not claimed. Report real test output; say what you could not check.
- Cannot share screenshots or images with AI (company policy): never ask for them. Ask them to describe what
  looks wrong in the app.
- Manager-level pressure: a hackathon submission was set for 12 Nov 2026 (demo freeze about 9 Nov).
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

- **The installed Dart is 3.13.5 but `pubspec.yaml` needs `^3.13.7`**, so `pub get` fails in the real folder. We work
  around it with a **copy at `D:\Android\cache\tmp\sellix_copy`** whose `pubspec.yaml` says `^3.13.5`. Edit the real
  files, then sync: `cp -r lib test /d/Android/cache/tmp/sellix_copy/` and run analyze/test/run there. Decide with the
  user whether to lower the real constraint (open question, section 7).
- Run the web app (port 8080 is what the backend's CORS allows), as its own background task:
  `cd /d/Android/cache/tmp/sellix_copy; cmd //c "D:\Android\flutter-direct.cmd run -d web-server --web-port 8080 --dart-define=DEV_ACCESS_TOKEN=<token> --dart-define=API_BASE_URL=http://localhost:8000" < /dev/null`
  with `run_in_background`. Nesting it in `( ... &)` inside another command dies when that command ends.
- Release builds ignore `DEV_ACCESS_TOKEN`. No APK has been built yet (`build apk --release --dart-define=API_BASE_URL=https://...`).

| Thing | Value |
|---|---|
| Dev API / web app / eval server | `:8000` / `:8080` / `:8001` |
| Dev shop "Sweet Crumbs" | merchant id `88fa6847-ea60-48d3-9be7-4877c2073130`, agent engine `v2`, DB `sellix` |
| Test DB / temporary DBs | `sellix_test` (pytest recreates it); `sellix_evals`, `sellix_load` are created and dropped by hand |
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

## 4. What changed in the last sessions (7 Nov 2026)

Everything below is committed and tested. Test totals at the end: **backend 415 passed**, **Flutter 334 passed
(19 skipped, live tests)**, `ruff` and `basedpyright` clean, Flutter `analyze` clean.

### 4.1 Stock, orders, concurrency
- Stock is a ledger: `daily_stock` has one row per variant per date (`available = opening + restocked - held - sold - counter_sales`, never below 0 by a check constraint). An order holds stock for 15 minutes, `record_payment` turns holds into sales.
- **Fixed a real deadlock**: two customers ordering the same items in opposite order made Postgres abort one. Lines are now locked in variant-id order (`orders/service.py`).
- `tests/integration/test_concurrency.py`: 40 buyers for 10 items sell exactly 10; pre-order days hold the right date; double payment sells once; cancel-vs-pay stays consistent.

### 4.2 Pre-order availability (backend + app)
- Migration `20261107000000_availability_policy.sql`: `products.available_on` (sold on that one day only) and `products.order_by_date` (last day to order). The total quantity is that day's `daily_stock.opening`.
- `quote()` refuses a one-day item on another day or after its last order date (`catalog.VariantCatalogInfo.ordering_problem`). Customer menus and the agent hide closed items; the merchant still sees them.
- `PATCH /v1/products/{id}` takes `available_on` / `order_by_date` (null clears, omitted keeps). `PUT /v1/stock/upcoming` takes `one_day_only` and `last_order_date`: products it creates become that day's items; a one-day item can't be stocked on another day (422).
- Fixed a contract bug: the app expected `variant_id`, `opening` etc. from `/v1/stock/upcoming` that the API never sent (the Coming days screen would crash). The API sends them now.
- **App**: new `features/stock/day_stock_screen.dart` (route `/stock-for?date=`): set stock for a later day like today's flow (type it, add an item, new product, counts), an "Only on this day" switch and a "Last day to order" picker. The Catalogue tab shows every product with "Only 15 Nov · order by 12 Nov"; today's lists hide other days' one-day items (`StockView.onTodaysList`).

### 4.3 Production hardening
- **Config** (`core/config.py`, `.env.example`): `DB_POOL_SIZE`, `DB_MAX_OVERFLOW`, `DB_POOL_TIMEOUT_SECONDS`, `DB_STATEMENT_TIMEOUT_MS`, `JOBS_POOL_MAX_SIZE`, `WORKER_CONCURRENCY`, rate-limit settings. Each API process has its own pool; a running agent turn holds one more connection for its lock.
- **Processes**: `backend/Dockerfile` (API default, `python -m app.worker` for the worker), `docker-compose.yml` (db, api with `API_WORKERS`, separate worker), `render.yaml` (API with `--workers 2`, separate worker service). Built and smoke-tested the image (2 server processes answer `/health`); the compose stack and Render blueprint were **not** run end to end.
- **Rate limits** (`core/ratelimit.py`): per signed-in user 240/min, auth endpoints 20/min per address, webhooks 600/min; `/health` exempt. Counted **per API process** (N processes = up to N times the limit); move to Redis for hard limits.
- **Tenant isolation**: `tests/integration/test_tenant_isolation.py` calls every `/v1` endpoint that takes an id as another shop (a guard test fails if a new one isn't listed). It found and we fixed `PUT /v1/stories/posts/{product_id}` letting shop B link to shop A's product.
- **Load test**: `backend/loadtest/` (Locust, `uv add --group load`). Baseline on this Windows laptop, 2 workers, 80 simulated owners, 60 s: ~35 req/s, 0 failures, median 47 ms, p95 ~500 ms (`GET /v1/today` slowest, p95 ~940 ms). Not a production number.
- **Dev tooling**: `issue-token --minutes N` (up to 1440, refused in prod); `agent-health --days N` (turn outcomes, fallback rate, p50/p95, cost, top errors).
- **Locks**: `core/locks.py` Postgres advisory lock; `agent.engine.run_turn` runs one copy of a chat's turn at a time (a redelivered job or the sweeper used to run a second copy and send a contradictory holding message).
- **Model gateway** (`agent/llm.py`): the circuit breaker counts a failed *call* once (after retries), only for service failures (a 400 content-filter refusal no longer counts), opens after 3 within 60 s, 30 s cooldown (was: per attempt, 2 minutes: flagged messages could switch the agent off for a whole shop). Connect timeout 5 s; each model call is also bounded by the turn deadline (60 s, was 30).

### 4.4 The agent (v2 engine)
How a turn works: `agent/context.py` picks a **playbook** with plain regexes on the stage and the customer's message (`choose_playbook`), builds the system prompt from `base.md` + the playbook + `context.md` (shop profile, today's menu, "Coming up" pre-orders with order-by dates, stage, draft, open questions), then `engine._loop` lets the model call tools until `send_reply` passes the output checks (`guardrails/output.py`). Prompts live in `agent/prompts/` with a `CHANGELOG.md` (every prompt change gets a row + an eval result).

Behaviour fixes this session (each has tests and, where useful, a live-eval scenario):
- **Owner answers**: a turn triggered by the owner's answer uses `playbook.owner_answer` (pass the answer on, don't repeat the menu), can't call `ask_shop_owner` again, and a near-repeat of the last reply is rejected. If the model fails entirely the customer gets "Update from the shop: <owner's words>" (`templates/owner_answer_relay.yaml`) instead of the generic holding message.
- **Suggested answers** are data now: migration `20261107010000_escalation_suggested_answers.sql` (`escalations.suggested_answers`), `GET /v1/questions` returns them; the app shows them as chips on the Needs-you card (tap fills the answer sheet) and as buttons in the chat (tap goes to the "Send this?" check). Old questions with the glued-on "Suggested answers:" line are parsed.
- **Voice**: no self-introduction, no "sir/madam" or guessed gender, short, "we" for the shop. **Honesty rule (deliberate)**: the agent never claims to be human; if a customer sincerely asks whether it is a person/bot/AI it says, in one friendly sentence, that it is the shop's virtual assistant and the owner steps in when needed. Code rejects unprompted "I am X's assistant"/"as an AI" and, after one repair attempt, cleans tone slips up (`tidy_style`) instead of falling back.
- **Any kind of shop**: `get_product_details` returns every saved attribute (fabric, size notes, care), not only food fields; routing regexes cover size/colour/fabric/returns/skin; prompts are not food-specific. Not supported: appointment/slot bookings, shipping charges or courier tracking.
- **Greeting vs menu**: a greeting lists no products (`small_talk@3`); "what do you have / anything else" uses the new `playbook.menu` (at most six items, then a narrowing question or the menu photo; plus the open pre-orders, enforced by a soft output check).
- **Pre-orders**: items under "Coming up" are open for booking: the agent says yes and takes the order. `ask_shop_owner` has a `confidence` (0-100; 75+ is sent back once) and a code check sends back plain "is the listed pre-order available?" questions. Both are capped at 2 refusals per turn.
- **Ordering of the chat**: `engine.causal_order` puts each reply right after the message it answered (replies record `trigger_id`), so a customer's "okay" that arrived while a reply was being written isn't answered with the same text again.
- Fallbacks: one open "assistant couldn't finish" question per chat during an outage; none if the agent already asked the owner in that turn. Health words ("eggless") are allowed in a reply that hands the question to the shop after the owner was asked.

### 4.5 Evals
`evals/run.py` multi-turn runner (new: `owner_answers` turns that answer an open question and wait for the follow-up job; `--seed-preorder` that sets up a "Diwali cake" pre-order). Datasets: `scenarios`, `adversarial`, `owner_answers`, `any_shop` (clothing, jewellery, skincare), `preorders_and_menu`: **40 scenarios**. Every turn is also checked for internal item ids, unfilled `[[tokens]]` and stiff phrases. Final results on the last code: **40/40**, then **39/40** (the miss was a dropped connection to the Azure endpoint, 7 network errors in that run). Run them twice; a language model varies. See `evals/README.md`.

## 5. Decisions and why (don't undo without asking)

| Decision | Why |
|---|---|
| The agent won't deny being an AI to a sincere question | Deception, and some jurisdictions require disclosure. It just doesn't volunteer it |
| We don't get around Netskope | It's the company's security control. Real fixes: ask the network team to allow `www.instagram.com`, `api.instagram.com`, `graph.instagram.com`, `graph.facebook.com`; or run the backend somewhere outside the company network (cloud). Moving the login to the phone would not help: the server also calls Meta's API (token exchange, sending DMs), and the app secret must never go into the app |
| One-day items are an explicit `one_day_only` flag, not inferred | A new product with tomorrow's stock could be a special or a regular item starting tomorrow |
| Playbook choice stays regex-based | Cheap, testable. A small classifier is the next step if misrouting shows up in traces |
| Rate limits are in memory | Good enough to stop runaway clients; use Redis for hard guarantees |
| Launch real merchants in `draft` engine mode first | Each reply waits for the merchant's approval; move to live after watching `agent-health` for a week |

## 6. Where things are

- Agent: `backend/app/modules/agent/` (`engine.py` loop and fallbacks, `context.py` routing and prompt build, `tools/`, `guardrails/output.py`, `llm.py`, `prompts/`).
- Orders and stock: `backend/app/modules/{orders,inventory,catalog}/service.py`. Payments: `modules/payments/`.
- API: `backend/app/api/v1/`. Jobs: `core/jobs.py`, each module's `tasks.py`. Locks/limits: `core/locks.py`, `core/ratelimit.py`.
- Tests: `backend/tests/{unit,integration}/` (integration builds a fresh DB from the real migrations).
- Flutter: `frontend/flutter_app/lib/{core,design,features}/`; tests in `test/` (fake API in `test/support/fake_sellix_api.dart`).

## 7. Open items, risks, what to do next

**Needs a decision from the user**
1. Lower `sdk: ^3.13.7` to `^3.13.5` in the real `pubspec.yaml`? (Teammates' Dart may be newer. Today we run from a copy.)
2. How to get Instagram working: network-team allowlist vs. a cloud-hosted backend (Render is drafted). Until then, test with the simulator and the dev token.
3. Push the three local commits (they stay local until the user pushes).

**Do next (suggested order)**
1. Push, open a pull request, have a teammate review (the diff is large: 86 files in `86e4307` plus the three commits above).
2. Deploy the backend off the laptop (Render + Supabase), put real secrets in the host's environment, run the worker as its own service, set `FORWARDED_ALLOW_IPS`, and apply migrations with `supabase db push` (there is no tracker for the raw SQL files).
3. Build an APK against that public `https` URL; sign in with Instagram on the phone.
4. First real merchant in `draft` mode; watch `agent-health`; set `LLM_MODELS` to a second model as a backup; consider an alert on the fallback rate.
5. Seed a demo-data script (products, customers, chats, orders) so the dashboard isn't empty (offered, not built).

**Known gaps**
- The app can't edit an existing product's availability (`available_on` / `order_by_date`): only the Coming days flow sets them; Dart `ProductUpdate` lacks the fields and the product screen doesn't show them.
- Answering a payment question with "I got the payment directly" does not mark the order paid (use Mark paid on the order). Worth linking the two.
- Customers who got a holding message during a model outage are not retried automatically afterwards.
- Order numbers (`ORD-1001...`) are global across shops and reveal the total volume. The "max 2 unpaid orders" check can be passed by two simultaneous confirms.
- Not done from the plan: live Meta spikes, push notifications, PayPal void/payee checks, perceptual hashes.
- Tamil and Hindi texts (`owner_answer_relay`, others) need a native speaker's review.
- Visual UI has never been looked at by Claude (no screenshots). The user checks the screens.
- Netskope-dependent network flakiness can make live evals fail; check `agent-health` errors (`ConnectError`, `circuit open`) before blaming the code.

**Ideas, lower priority**
- A small model to classify the turn instead of regex playbook routing.
- Redis-backed rate limits; per-merchant rate limits and budgets surfaced in the app.
- Appointment/slot booking and shipping fees for service and delivery-heavy shops.
- A screen in the app to read the simulator conversation and traces (`replay-turn` exists as a CLI).

## How to keep this handoff

**This is a standing instruction for every Claude session on this repo** (also in `CLAUDE.md`, which Claude Code loads automatically).

1. **Start of a session:** read this file, then `git status` and `git log -3`. Trust the code over this file if they disagree, and fix the file.
2. **During:** when you decide something that isn't obvious from the code (a rule, a trade-off, a thing you refused to do and why), add a row to section 5.
3. **Before you end a session, or after any large piece of work:** update this file. Change the date; move finished items out of section 7; add what changed to section 4 (what, where, why, how it was checked, the test counts); add new traps to section 3; list new open items and decisions needed. Keep it accurate and short enough to read in a few minutes: delete stale text, don't pile on.
4. **Never put secrets** (keys, tokens, passwords, customer data) in this file.
5. If you create or change a migration, a command, a port or a workaround, say so here.
6. Also keep the memory notes (`MEMORY.md`) in step: the memory points here.
