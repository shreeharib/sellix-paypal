# Handoff

The one file a new Claude session reads first. It says what sellix is, what is built, what changed in the
last session, what is open, and how to run and check everything on this PC.

**What to do next is in [NEXT-PHASE.md](NEXT-PHASE.md)** (ordered tasks, decisions waiting on the user, the hackathon deadline).

**Keep it true.** Whoever works on sellix updates this file before ending a session or after any big
piece of work (see [How to keep this handoff](#how-to-keep-this-handoff)). Last updated: **9 Nov 2026**.

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

### 4.5 Evals
`evals/run.py` multi-turn runner (new: `owner_answers` turns that answer an open question and wait for the follow-up job; `--seed-preorder` that sets up a "Diwali cake" pre-order). Datasets: `scenarios`, `adversarial`, `owner_answers`, `any_shop` (clothing, jewellery, skincare), `preorders_and_menu`: **40 scenarios**. Every turn is also checked for internal item ids, unfilled `[[tokens]]` and stiff phrases. Final results on the last code: **40/40**, then **39/40** (the miss was a dropped connection to the Azure endpoint, 7 network errors in that run). Run them twice; a language model varies. See `evals/README.md`.

### 4.6 PayPal for a rupee shop (8 Nov, committed in `c3b2994`)
The PayPal sandbox refuses INR (`422 CURRENCY_NOT_SUPPORTED`, checked live), so rupee orders never got a PayPal link: they got `payment_offline` plus an owner question. Now the order and the chat stay in ₹ and **PayPal charges dollars at the live rate**.
- `payments/fx.py`: `frankfurter.dev`, then `open.er-api.com`, then `FX_FALLBACK_INR_PER_USD` (default 94); cached `FX_CACHE_MINUTES` (60); a source more than 30% from the fixed rate is ignored. The dollar amount is rounded **up** (₹899 at 93.92 = $9.58). Only INR is convertible (`fx.CONVERTIBLE`).
- `payments.service.start_checkout` (`create_checkout` wraps it) stores the **dollar** amount on the `payments` row; asking again returns that same row (no second PayPal order, amount never changes). `_record_verified` marks the whole ₹ order paid only if PayPal captured exactly the amount asked; anything else is `amount_mismatch` as before.
- `payments.service.settle_open_payments` + job `settle_open_payments` (every minute, `payments/tasks.py`): captures approved orders when the return page or webhook never arrived (a phone that can't open the laptop's address, a dead tunnel). The customer's chat confirmation comes from `conversations.after_payment`. In dev the API runs the worker in-process, so restart the API to get it.
- Template `payment_link@2` says "PayPal charges $X at today's rate" (Tamil/Hindi lines need a native speaker). The agent passes `charge`; the v1 engine does not show it.
- `GET /v1/orders/{id}/payment-link` no longer invents a UPI id (`<shopname>@upi`) when the shop has none: it uses PayPal.
- Checked: full backend suite 425 passed and 1 failed (a test that relied on the invented UPI id; fixed, and `test_api.py` now passes 25 including 2 new ones; the full suite was not re-run after that last edit); `ruff` and `basedpyright` clean; a real sandbox order was created from a live rate (₹899 = $9.58 at ₹93.92). **Not yet done:** a sandbox buyer approving and the order turning paid; the live agent evals (the template is sent by code, but the flow is worth one run).
- `PUBLIC_BASE_URL` in `.env` was a dead Cloudflare quick tunnel; on 8 Nov (user's OK) it was set to `http://localhost:8000`. PayPal sends the buyer's browser to `<PUBLIC_BASE_URL>/payments/paypal/return` after approval, so with localhost the buyer must approve **in a browser on this laptop**. A phone needs a live HTTPS address (Render, or a tunnel); the poll job then still captures the payment but the phone shows an error page. PayPal webhooks (registered for the old tunnel) don't arrive until a public address is set and re-registered. The Instagram login callback also uses this value (already blocked from this laptop).

### 4.7 Payment retries, the payment simulator, order references (8 Nov, committed in `c3b2994`)
- **Settings** (`core/config.py`, `.env.example`): `PAYMENT_PROVIDER=paypal|simulator` (default paypal; the simulator is refused when `APP_ENV=prod`), `PAYMENT_MAX_ATTEMPTS=3` (links per order, the first included), `PAYMENT_RETRY_COOLDOWN_SECONDS=60`, and the retry window is `PAYMENT_HOLD_MINUTES`. `PAYPAL_MOCK_RESPONSE` (sandbox only) sends PayPal's negative-testing header `PayPal-Mock-Response` on every PayPal call. PayPal itself has no hosted page where a tester picks the outcome (docs checked 8 Nov); its tools are that header and the webhook simulator (public URL needed, events not tied to real orders).
- **Retry rules** (`payments.service._retry_policy`, `retry_status`, `RetryRefused(reason, wait_seconds)`): while a link is open, asking again returns the same link; after a rejected payment a new link needs the cooldown to have passed, fewer than the max attempts used, and the hold still running. A real-PayPal retry is a new PayPal order (the request id includes the attempt). `GET /v1/orders/{id}/payment-link` answers 409 with the reason.
- **A rejected payment** (`conversations.tasks._payment_failed`, code, no model): the customer gets `payment_declined` (tries left, cooldown) with a **"New payment link" button** (`RETRY:<order id>`, handled in code by `engine._apply_retry_tap` like Confirm/Change). Tapping early gets `payment_retry_wait`. No tries or no time left: the order is cancelled (stock released) and `payment_gave_up` is sent.
- **The simulator** (`payments/simulator.py`, `app/webhooks/simulator.py`): the payment link opens `<PUBLIC_BASE_URL>/payments/simulator/<id>`, a page with **Accept payment** and **Reject payment**. A button signs a webhook (HMAC, key derived from `SESSION_SIGNING_KEY`, header `x-simulator-signature`) and delivers it to `POST /webhooks/simulator`; it goes into the same inbox (source `simulator`), job `process_simulator_event` applies it via `payments.handle_simulator_event`, then `conversations.after_payment`. Payment rows use provider and method `simulator`; an order paid through it shows actor `simulator` in its history. To use it: set `PAYMENT_PROVIDER=simulator` in `backend/.env`, restart the API.
- **Migration** `supabase/migrations/20261108000000_payment_simulator_provider.sql` widens four CHECK constraints (payments provider and method, webhook_events source, order_events actor). Applied to dev DB `sellix` on 8 Nov; apply it to any other database (the migration loop in section 3).
- **Model-down fallback**: for `payment_received` and `hold_expired` events the engine sends the fixed templates `event_payment_received` / `event_hold_expired` instead of the generic holding text (`engine._EVENT_FALLBACKS`).
- **Order references**: `prompts/context.md@5` lists "Orders waiting for payment: #1003"; `cancel_order` and `resend_payment_link` take `order` (the number; the id is still accepted). Before this, every real cancel failed with `unknown_order`.
- Checked: unit and integration tests for the policy, the simulator page to webhook to job to order, cooldown, cancel on the last failed try, signature and production guard, the RETRY tap, the model-down fallbacks, and cancel by number with the id hidden from the model. Tamil and Hindi lines in the new templates need a native speaker's review.

### 4.8 Shop-type templates (8 Nov, committed in `c3b2994`)
- The add-product form follows the shop's type. **Four stock behaviours are fixed in code** (`daily` fresh batches, `inventory` keep until sold, `made_to_order`, `unlimited`); templates only choose among them, and a **shelf life is asked only for `daily`**. Detail fields (size, shade, allergens ...) are data.
- `shop_profile/shop_types.yaml`: `bakery`, `jewellery`, `beauty`, `plants`, `handmade_gifts`, `dress_shop`, `other`. A shop's template is its `shop_type` answer, else the first type whose keywords match its free-text `category` (order in the file matters: "fashion jewellery" is jewellery). Models are in `shop_profile/schemas.py` (`ProductSchema` ...), the lookup is `shop_profile.service.product_schema` / `shop_type_choices` (module boundary rule: other modules import only `service` and `schemas`).
- API: `GET /v1/product-schema` (this shop's template), `GET /v1/shop-types` (`[{id, label}]`); `OnboardingAnswers.shop_type`, kept when a save omits it (a save replaces all other answers).
- To add a shop type: add an entry to the yaml and a row in `tests/unit/test_shop_types.py`. Changing a template never rewrites existing products; bump `version`.
- Demo types are bakery and dress shop; all seven are wired.
- **App** (`frontend/flutter_app`): `ProductSchema` model, `SellixApi.productSchema()` / `shopTypes()`, `productSchemaProvider` (falls back to a built-in schema if the call fails) and `shopSchemaProvider`; `ShopTerms` survives only as the fallback source. The add-product form asks "How do you stock this?" from the schema's stock modes (hidden when a type allows one) and shows shelf life only for fresh batches (`StockTypeQuestion` in `stock_widgets.dart`, replacing `ShelfPicker`); detail inputs (chips with "Other", or one line) come from `detail_fields` and are saved as product `attributes`. The Settings shop-type picker lists `GET /v1/shop-types` and saves `shop_type` plus `category` (the type's label); `OnboardingAnswers` carries `shopType` through every save. The onboarding stock step uses the schema and no longer re-sends an untouched row's stock type (it used to rewrite products to daily). `StockRow.stockMode` is nullable so the catalogue wins when a row lacks it. A new product added from "Set today's stock" now appears in the list without a reload. A typed stock line for an unknown product with no price asks for the price instead of showing the API error. The order screen shows the server's 409 text for payment-link retries ("Wait 40 seconds ...") and a debug assertion in "Try again" was fixed.
- Not done in the app: the onboarding first step still picks from the app's own category table (it keeps `shop_type` when the category is unchanged and clears it when it changes); one-day (pre-order) items still can't be edited; the "+" report is unresolved (section 7).

### 4.9 UI vs backend audit and fixes (8 Nov)
A read-only audit compared every Flutter API call with the backend OpenAPI. Fixed: `/v1/today` stock rows now carry `stock_mode` and `shelf_life_days` (the app defaulted a missing one to "daily", and the onboarding stock step re-sent it, silently rewriting products); `POST /v1/today/parse-stock-text` now needs sign-in; the orders `payment_status` filter accepts `unpaid`. Open items are listed under "Found on 8 Nov".

**Checks run on 8 Nov:** backend 470 passed, `ruff` and `basedpyright` clean, the 4 real PayPal sandbox tests pass; Flutter `analyze` clean and 400 passed (20 skipped live tests); the app's live contract tests (18, `test/api/live_contract_test.dart`, run with `LIVE_API_URL` and `LIVE_TOKEN` against a server on the new code) all pass, so the app parses every real answer including `/v1/product-schema`. Live evals (real model): the first run was 29/31 and caught that `playbook.payment_problem` still told the model to ask the owner to cancel (`cancel_order` itself worked); after `payment_problem@2` the main set (scenarios, adversarial, any_shop) was 31/31 twice and owner answers + pre-orders 11/11. Not checked: the new screens in a real browser (nobody has looked at them), a real sandbox buyer paying with the converted dollar amount, and the simulator pages by eye.

### 4.10 Typed "ok" no longer orders; off-topic routing; no "sir / madam" (9 Nov, committed in `c3b2994`)
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

### 4.11 Agent harness explainer page (9 Nov)
- **`docs/agent-harness.html`**: one page that explains the backend agent end to end (webhook, inbox, turn job, the engine loop, the 20 tools, the 11 playbooks and how one is chosen, how context is built, memory, stages, guardrails, duplicate protection, the owner loop, payments, engine modes, evals, status, interview questions). Written from the code at `c3b2994`, with status taken from this file. Also published as a private claude.ai artifact for sharing: https://claude.ai/artifact/Y9tLyWixaQYSP8sP3dLiSy (publish the same file again to update that link).
- **`docs/conversation-trace.html`** (companion, private artifact https://claude.ai/artifact/6J1rVtck3vFX29c6rjMuYo): one example chat (2 chocolate cookies, pickup, add a brownie, "Perfect, place the order", PayPal payment) drawn as sequence diagrams of the calls in order (API, worker, Postgres, engine, tools, model), with the playbook, tools, stage and the Postgres rows changed after each of its 5 turns. The playbook for each message, the confirmation result, the quote cards and the payment message were produced by the real functions and templates; ids, prices and wording are examples. The diagrams were generated by a throwaway script in a session scratchpad (not in the repo): edit the HTML directly.
- Checked: the tools per stage and the prompt counts were printed by importing `registry.TOOLS` and the prompt store; the page's JavaScript copy of `choose_playbook` and `affirmation.classify` gave the same answers as the Python on 58 messages (headless Chrome). No code changed, so no tests or evals were run.
- **Found, not fixed:** (1) (addressed by the router, section 4.12; the fallback rules still have the gap) "what else do you have" never routes to `playbook.menu` (`_MENU` matches "anything else", not "what else"): it gets `new_order` in browsing and `payment_problem` while paying. (2) Draft mode holds only `send_reply`'s message; the quote card, payment link and templates that tools queue go out at once. (3) `lookup_story` and `describe_image` have `writes = False` but save their vision results, so shadow mode writes that cache. (4) New merchants default to `agent_engine = 'v1'` (migration default).

### 4.12 The playbook is chosen by a model call (9 Nov, uncommitted)
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
3. Open a pull request for `feat/preorders-and-agent-hardening` and have a teammate review it.

**Do next (suggested order)**
1. Pull request and review (the diff is large: 61 backend files in `86e4307` plus the commits above).
2. Deploy the backend off the laptop (Render + Supabase), put real secrets in the host's environment, run the worker as its own service, set `FORWARDED_ALLOW_IPS`, and apply migrations with `supabase db push` (there is no tracker for the raw SQL files).
3. Build an APK against that public `https` URL; sign in with Instagram on the phone.
4. First real merchant in `draft` mode; watch `agent-health`; set `LLM_MODELS` to a second model as a backup; consider an alert on the fallback rate.
5. Seed a demo-data script (products, customers, chats, orders) so the dashboard isn't empty (offered, not built).

**Found on 8 Nov 2026 (from simulator chats and a UI-vs-backend audit): status**

Fixed (sections 4.6 to 4.9, committed in `c3b2994`): PayPal for a rupee shop; the cancel / resend tools that could not work with the real model; the generic "I'll check with the shop" sent for a payment or expiry event when the model was down; "1 week" / "until sold" never saved; the stock type missing from `/v1/today`; the stale owner answer (the two questions that caused it, payment details and cancel, no longer arise); one add-product form for every kind of shop.

Fixed on 9 Nov (section 4.10): a typed "ok" placing an order; off-topic messages getting the order playbook; "Introduce yourself" and "Sir or madam" in the profile and the onboarding.

Still open:
1. "+" on the stock screens: fixed on 9 Nov (section 4.10) and checked in headless Chrome; the user still has to confirm on their screen.
2. **PayPal webhooks can't reach this laptop** (`PUBLIC_BASE_URL=http://localhost:8000`). Real sandbox payments still
   complete: the buyer's browser returns to `/payments/paypal/return` on this laptop, which captures, and the
   `settle_open_payments` job (every minute) captures any approved order the return missed. A real webhook needs a
   public https address (Render, or a tunnel) registered in the PayPal developer dashboard, with `PAYPAL_WEBHOOK_ID`
   for that address. On 9 Nov the user asked to drop the simulator for the demo; the dev API was switched to
   `PAYMENT_PROVIDER=paypal`, the simulator code stays (off by default; deleting it is the user's call).
3. **Deadlock in `expire_unpaid_orders` when several copies run at once** (seen 9 Nov after the laptop slept: missed minutes ran together). `orders.service.expire_due` releases stock order by order in one transaction, each order's lines in variant order, so two copies with different orders can lock the same `daily_stock` rows in opposite order. Postgres aborts one; the next run expires those orders, so it heals itself, but a worker that was down will log errors. Fix: release all of a batch's lines sorted by (variant, date), or take an advisory lock (`core/locks.py`) so one copy runs at a time.
4. Audit leftovers (not fixed): one-day (pre-order) items cannot be edited in the app; the "Left from yesterday" carry is a phone-only log (a second phone or reinstall can carry twice); a new product takes 2 to 3 calls for details and aliases; no endpoint to send a merchant message or create an order from a chat; refund is full and PayPal only; the three automations screens and notification prefs are local only; Settings > Rules cannot list or delete saved "always" rules; customers / insights / orders lists are silently capped (100 / 200) with no paging; "Remove product" has no backend; `needed_by` is free text although `scheduled_date` exists; `GET /v1/products` is N+1; `/v1/stories/*`, `/v1/products/search`, `/today/rollover/auto`, `POST /orders/{id}/invoice` are unused by the app; the web app is only allowed from `http://localhost:8080` (`WEB_APP_ORIGINS`) and the Instagram sign-in needs an https `PUBLIC_BASE_URL`. Voice, photo, "Same as yesterday", timed pause, WhatsApp, Google/Apple sign-in, cash on delivery, share link and plan/billing are disabled in the UI with no backend.

5. Agent findings of 9 Nov (section 4.11): add "what else" to `_MENU` (with a routing test and a live-eval run); decide whether draft mode should also hold the messages tools queue; consider `writes = True` for the two vision tools.

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
